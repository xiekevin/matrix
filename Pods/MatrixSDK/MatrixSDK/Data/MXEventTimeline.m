/*
 Copyright 2016 OpenMarket Ltd

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#import "MXEventTimeline.h"

#import "MXSession.h"
#import "MXMemoryStore.h"

#import "MXError.h"

#import "MXEventsEnumeratorOnArray.h"

NSString *const kMXRoomInviteStateEventIdPrefix = @"invite-";

@interface MXEventTimeline ()
{
    // The list of event listeners (`MXEventListener`) of this timeline.
    NSMutableArray *eventListeners;

    // The historical state of the room when paginating back.
    MXRoomState *backState;

    // The state that was in the `state` property before it changed.
    // It is cached because it costs time to recompute it from the current state.
    // This is particularly noticeable for rooms with a lot of members (ie a lot of
    // room members state events).
    MXRoomState *previousState;

    // The associated room.
    MXRoom *room;

    // The store to store events,
    id<MXStore> store;

    // The events enumerator to paginate messages from the store.
    id<MXEventsEnumerator> storeMessagesEnumerator;
 
    // MXStore does only back pagination. So, the forward pagination token for
    // past timelines is managed locally.
    NSString *forwardsPaginationToken;
    BOOL hasReachedHomeServerForwardsPaginationEnd;
    
    /**
     The current pending request.
     */
    MXHTTPOperation *httpOperation;
}
@end

@implementation MXEventTimeline

#pragma mark - Initialisation
- (id)initWithRoom:(MXRoom*)room2 andInitialEventId:(NSString*)initialEventId
{
    // Is it a past or live timeline?
    if (initialEventId)
    {
        // Events for a past timeline are stored in memory
        MXMemoryStore *memoryStore = [[MXMemoryStore alloc] init];
        [memoryStore openWithCredentials:room2.mxSession.matrixRestClient.credentials onComplete:nil failure:nil];

        self = [self initWithRoom:room2 initialEventId:initialEventId andStore:memoryStore];
    }
    else
    {
        // Live: store events in the session store
        self = [self initWithRoom:room2 initialEventId:initialEventId andStore:room2.mxSession.store];
    }
    return self;
}

- (id)initWithRoom:(MXRoom*)room2 initialEventId:(NSString*)initialEventId andStore:(id<MXStore>)store2
{
    self = [super init];
    if (self)
    {
        _timelineId = [[NSUUID UUID] UUIDString];
        _initialEventId = initialEventId;
        room = room2;
        store = store2;
        eventListeners = [NSMutableArray array];

        if (!initialEventId)
        {
            _isLiveTimeline = YES;
        }

        _state = [[MXRoomState alloc] initWithRoomId:room.roomId andMatrixSession:room.mxSession andDirection:YES];
        
        _roomEventFilter = [[MXRoomEventFilter alloc] init];
    }
    return self;
}

- (void)initialiseState:(NSArray<MXEvent *> *)stateEvents
{
    for (MXEvent *event in stateEvents)
    {
        [self handleStateEvent:event direction:MXTimelineDirectionForwards];
    }
}

- (void)destroy
{
    [room.mxSession resetReplayAttackCheckInTimeline:_timelineId];

    if (httpOperation)
    {
        // Cancel the current server request
        [httpOperation cancel];
        httpOperation = nil;
    }
    
    if (!_isLiveTimeline)
    {
        // Release past timeline events stored in memory
        [store deleteAllData];
    }
}


#pragma mark - Pagination
- (BOOL)canPaginate:(MXTimelineDirection)direction
{
    BOOL canPaginate = NO;

    if (direction == MXTimelineDirectionBackwards)
    {
        // canPaginate depends on two things:
        //  - did we end to paginate from the MXStore?
        //  - did we reach the top of the pagination in our requests to the home server?
        canPaginate = (0 < storeMessagesEnumerator.remaining)
            || ![store hasReachedHomeServerPaginationEndForRoom:_state.roomId];
    }
    else
    {
        if (_isLiveTimeline)
        {
            // Matrix is not yet able to guess the future
            canPaginate = NO;
        }
        else
        {
            canPaginate = !hasReachedHomeServerForwardsPaginationEnd;
        }
    }

    return canPaginate;
}

- (void)resetPagination
{
    [room.mxSession resetReplayAttackCheckInTimeline:_timelineId];

    // Reset the back state to the current room state
    backState = [[MXRoomState alloc] initBackStateWith:_state];

    // Reset store pagination
    storeMessagesEnumerator = [store messagesEnumeratorForRoom:_state.roomId];
}

- (MXHTTPOperation *)resetPaginationAroundInitialEventWithLimit:(NSUInteger)limit success:(void (^)())success failure:(void (^)(NSError *))failure
{
    NSParameterAssert(success);
    NSAssert(_initialEventId, @"[MXEventTimeline] resetPaginationAroundInitialEventWithLimit cannot be called on live timeline");

    [room.mxSession resetReplayAttackCheckInTimeline:_timelineId];
    
    // Reset the store
    [store deleteAllData];

    forwardsPaginationToken = nil;
    hasReachedHomeServerForwardsPaginationEnd = NO;

    // Get the context around the initial event
    return [room.mxSession.matrixRestClient contextOfEvent:_initialEventId inRoom:room.roomId limit:limit success:^(MXEventContext *eventContext) {

        // And fill the timelime with received data
        [self initialiseState:eventContext.state];

        // Reset pagination state from here
        [self resetPagination];

        [self addEvent:eventContext.event direction:MXTimelineDirectionForwards fromStore:NO];

        for (MXEvent *event in eventContext.eventsBefore)
        {
            [self addEvent:event direction:MXTimelineDirectionBackwards fromStore:NO];
        }

        for (MXEvent *event in eventContext.eventsAfter)
        {
            [self addEvent:event direction:MXTimelineDirectionForwards fromStore:NO];
        }

        [store storePaginationTokenOfRoom:room.roomId andToken:eventContext.start];
        forwardsPaginationToken = eventContext.end;

        success();
    } failure:failure];
}


- (MXHTTPOperation *)paginate:(NSUInteger)numItems direction:(MXTimelineDirection)direction onlyFromStore:(BOOL)onlyFromStore complete:(void (^)())complete failure:(void (^)(NSError *))failure
{
    MXHTTPOperation *operation;

    NSAssert(nil != backState, @"[MXEventTimeline] paginate: resetPagination or resetPaginationAroundInitialEventWithLimit must be called before starting the back pagination");

    NSAssert(!(_isLiveTimeline && direction == MXTimelineDirectionForwards), @"Cannot paginate forwards on a live timeline");
    
    NSUInteger messagesFromStoreCount = 0;

    if (direction == MXTimelineDirectionBackwards)
    {
        // For back pagination, try to get messages from the store first
        NSArray *messagesFromStore = [storeMessagesEnumerator nextEventsBatch:numItems];

        if (messagesFromStore)
        {
            messagesFromStoreCount = messagesFromStore.count;
        }

        NSLog(@"[MXEventTimeline] paginate %tu messages in %@ (%tu are retrieved from the store)", numItems, _state.roomId, messagesFromStoreCount);

        if (messagesFromStoreCount)
        {
            @autoreleasepool
            {
                // messagesFromStore are in chronological order
                // Handle events from the most recent
                for (NSInteger i = messagesFromStoreCount - 1; i >= 0; i--)
                {
                    MXEvent *event = messagesFromStore[i];
                    [self addEvent:event direction:MXTimelineDirectionBackwards fromStore:YES];
                }

                numItems -= messagesFromStoreCount;
            }
        }

        if (onlyFromStore && messagesFromStoreCount)
        {
            complete();

            NSLog(@"[MXEventTimeline] paginate : is done from the store");
            return nil;
        }

        if (0 == numItems || YES == [store hasReachedHomeServerPaginationEndForRoom:_state.roomId])
        {
            // Nothing more to do
            complete();

            NSLog(@"[MXEventTimeline] paginate: is done");
            return nil;
        }
    }

    // Do not try to paginate forward if end has been reached
    if (direction == MXTimelineDirectionForwards && YES == hasReachedHomeServerForwardsPaginationEnd)
    {
        // Nothing more to do
        complete();

        NSLog(@"[MXEventTimeline] paginate: is done");
        return nil;
    }

    // Not enough messages: make a pagination request to the home server
    // from last known token
    NSString *paginationToken;

    if (direction == MXTimelineDirectionBackwards)
    {
        paginationToken = [store paginationTokenOfRoom:_state.roomId];
        if (nil == paginationToken)
        {
            paginationToken = @"END";
        }
    }
    else
    {
        paginationToken = forwardsPaginationToken;
    }

    NSLog(@"[MXEventTimeline] paginate : request %tu messages from the server", numItems);

    operation = [room.mxSession.matrixRestClient messagesForRoom:_state.roomId from:paginationToken direction:direction limit:numItems filter:_roomEventFilter success:^(MXPaginationResponse *paginatedResponse) {

        NSLog(@"[MXEventTimeline] paginate : get %tu messages from the server", paginatedResponse.chunk.count);

        [self handlePaginationResponse:paginatedResponse direction:direction];

        // Inform the method caller
        complete();

        NSLog(@"[MXEventTimeline] paginate: is done");

    } failure:^(NSError *error) {
        // Check whether the pagination end is reached
        MXError *mxError = [[MXError alloc] initWithNSError:error];
        if (mxError && [mxError.error isEqualToString:kMXErrorStringInvalidToken])
        {
            // Store the fact we run out of items
            if (direction == MXTimelineDirectionBackwards)
            {
                [store storeHasReachedHomeServerPaginationEndForRoom:_state.roomId andValue:YES];
            }
            else
            {
                hasReachedHomeServerForwardsPaginationEnd = YES;
            }

            NSLog(@"[MXEventTimeline] paginate: pagination end has been reached");

            // Ignore the error
            complete();
            return;
        }

        NSLog(@"[MXEventTimeline] paginate failed");
        failure(error);
    }];

    if (messagesFromStoreCount)
    {
        // Disable retry to let the caller handle messages from store without delay.
        // The caller will trigger a new pagination if need.
        operation.maxNumberOfTries = 1;
    }

    return operation;
}

- (NSUInteger)remainingMessagesForBackPaginationInStore
{
    return storeMessagesEnumerator.remaining;
}


#pragma mark - Homeserver responses handling
- (void)handleJoinedRoomSync:(MXRoomSync *)roomSync
{
    // Is it an initial sync for this room?
    BOOL isRoomInitialSync = (self.state.membership == MXMembershipUnknown || self.state.membership == MXMembershipInvite);

    // Check whether the room was pending on an invitation.
    if (self.state.membership == MXMembershipInvite)
    {
        // Reset the storage of this room. An initial sync of the room will be done with the provided 'roomSync'.
        NSLog(@"[MXEventTimeline] handleJoinedRoomSync: clean invited room from the store (%@).", self.state.roomId);
        [store deleteRoom:self.state.roomId];
    }

    // Build/Update first the room state corresponding to the 'start' of the timeline.
    // Note: We consider it is not required to clone the existing room state here, because no notification is posted for these events.
    for (MXEvent *event in roomSync.state.events)
    {
        // Report the room id in the event as it is skipped in /sync response
        event.roomId = _state.roomId;

        [self handleStateEvent:event direction:MXTimelineDirectionForwards];
    }

    // Update store with new room state when all state event have been processed
    if ([store respondsToSelector:@selector(storeStateForRoom:stateEvents:)])
    {
        [store storeStateForRoom:_state.roomId stateEvents:_state.stateEvents];
    }

    // Handle now timeline.events, the room state is updated during this step too (Note: timeline events are in chronological order)
    if (isRoomInitialSync)
    {
        for (MXEvent *event in roomSync.timeline.events)
        {
            // Report the room id in the event as it is skipped in /sync response
            event.roomId = _state.roomId;

            // Add the event to the end of the timeline
            [self addEvent:event direction:MXTimelineDirectionForwards fromStore:NO];
        }

        // Check whether we got all history from the home server
        if (!roomSync.timeline.limited)
        {
            [store storeHasReachedHomeServerPaginationEndForRoom:self.state.roomId andValue:YES];
        }
    }
    else
    {
        // Check whether some events have not been received from server.
        if (roomSync.timeline.limited)
        {
            // Flush the existing messages for this room by keeping state events.
            [store deleteAllMessagesInRoom:_state.roomId];
        }

        for (MXEvent *event in roomSync.timeline.events)
        {
            // Report the room id in the event as it is skipped in /sync response
            event.roomId = _state.roomId;

            // Add the event to the end of the timeline
            [self addEvent:event direction:MXTimelineDirectionForwards fromStore:NO];
        }
    }

    // In case of limited timeline, update token where to start back pagination
    if (roomSync.timeline.limited)
    {
        [store storePaginationTokenOfRoom:_state.roomId andToken:roomSync.timeline.prevBatch];
    }

    // Finalize initial sync
    if (isRoomInitialSync)
    {
        // Notify that room has been sync'ed
        [[NSNotificationCenter defaultCenter] postNotificationName:kMXRoomInitialSyncNotification
                                                            object:room
                                                          userInfo:nil];
    }
    else if (roomSync.timeline.limited)
    {
        // The room has been resync with a limited timeline - Post notification
        [[NSNotificationCenter defaultCenter] postNotificationName:kMXRoomDidFlushDataNotification
                                                            object:room
                                                          userInfo:nil];
    }
}

- (void)handleInvitedRoomSync:(MXInvitedRoomSync *)invitedRoomSync
{
    // Handle the state events forwardly (the room state will be updated, and the listeners (if any) will be notified).
    for (MXEvent *event in invitedRoomSync.inviteState.events)
    {
        // Add a fake event id if none in order to be able to store the event
        if (!event.eventId)
        {
            event.eventId = [NSString stringWithFormat:@"%@%@", kMXRoomInviteStateEventIdPrefix, [[NSProcessInfo processInfo] globallyUniqueString]];
        }

        // Report the room id in the event as it is skipped in /sync response
        event.roomId = _state.roomId;

        [self addEvent:event direction:MXTimelineDirectionForwards fromStore:NO];
    }
}

- (void)handlePaginationResponse:(MXPaginationResponse*)paginatedResponse direction:(MXTimelineDirection)direction
{
    // Check pagination end - @see SPEC-319 ticket
    if (paginatedResponse.chunk.count == 0 && [paginatedResponse.start isEqualToString:paginatedResponse.end])
    {
        // Store the fact we run out of items
        if (direction == MXTimelineDirectionBackwards)
        {
            [store storeHasReachedHomeServerPaginationEndForRoom:_state.roomId andValue:YES];
        }
        else
        {
            hasReachedHomeServerForwardsPaginationEnd = YES;
        }
    }

    // Process received events
    for (MXEvent *event in paginatedResponse.chunk)
    {
        // Make sure we have not processed this event yet
		[self addEvent:event direction:direction fromStore:NO];
    }

    // And update pagination tokens
    if (direction == MXTimelineDirectionBackwards)
    {
        [store storePaginationTokenOfRoom:_state.roomId andToken:paginatedResponse.end];
    }
    else
    {
        forwardsPaginationToken = paginatedResponse.end;
    }

    // Commit store changes
    if ([store respondsToSelector:@selector(commit)])
    {
        [store commit];
    }
}


#pragma mark - Timeline events
/**
 Add an event to the timeline.
 
 @param event the event to add.
 @param direction the direction indicates if the event must added to the start or to the end of the timeline.
 @param fromStore YES if the messages have been loaded from the store. In this case, there is no need to store
                  it again in the store
 */
- (void)addEvent:(MXEvent*)event direction:(MXTimelineDirection)direction fromStore:(BOOL)fromStore
{
    // Make sure we have not processed this event yet
    if (fromStore == NO && [store eventExistsWithEventId:event.eventId inRoom:room.roomId])
    {
        return;
    }

    // State event updates the timeline room state
    if (event.isState)
    {
        [self cloneState:direction];

        [self handleStateEvent:event direction:direction];

        // The store keeps only the most recent state of the room
        if (direction == MXTimelineDirectionForwards && [store respondsToSelector:@selector(storeStateForRoom:stateEvents:)])
        {
            [store storeStateForRoom:_state.roomId stateEvents:_state.stateEvents];
        }
    }

    // Decrypt event if necessary
    if (event.eventType == MXEventTypeRoomEncrypted)
    {
        if (![room.mxSession decryptEvent:event inTimeline:_timelineId])
        {
            NSLog(@"[MXTimeline] addEvent: Warning: Unable to decrypt event: %@\nError: %@", event.content[@"body"], event.decryptionError);
        }
    }

    // Events going forwards on the live timeline come from /sync.
    // They are assimilated to live events.
    if (_isLiveTimeline && direction == MXTimelineDirectionForwards)
    {
        // Handle here live redaction
        if (event.eventType == MXEventTypeRoomRedaction)
        {
            [self handleRedaction:event];
        }

        // Consider that a message sent by a user has been read by him
        MXReceiptData* data = [[MXReceiptData alloc] init];
        data.userId = event.sender;
        data.eventId = event.eventId;
        data.ts = event.originServerTs;

        [store storeReceipt:data inRoom:_state.roomId];
    }

    // Store the event
    if (!fromStore)
    {
        [store storeEventForRoom:_state.roomId event:event direction:direction];
    }

    // Notify listeners
    [self notifyListeners:event direction:direction];
}

#pragma mark - Specific events Handling
- (void)handleRedaction:(MXEvent*)redactionEvent
{
    NSLog(@"[MXEventTimeline] handle an event redaction");
    
    // Check whether the redacted event is stored in room messages
    MXEvent *redactedEvent = [store eventWithEventId:redactionEvent.redacts inRoom:_state.roomId];
    if (redactedEvent)
    {
        // Redact the stored event
        redactedEvent = [redactedEvent prune];
        redactedEvent.redactedBecause = redactionEvent.JSONDictionary;

        // Store the updated event
        [store replaceEvent:redactedEvent inRoom:_state.roomId];
    }
    
    // Check whether the current room state depends on this redacted event.
    if (!redactedEvent || redactedEvent.isState)
    {
        NSMutableArray *stateEvents = [NSMutableArray arrayWithArray:_state.stateEvents];
        
        for (NSInteger index = 0; index < stateEvents.count; index++)
        {
            MXEvent *stateEvent = stateEvents[index];
            
            if ([stateEvent.eventId isEqualToString:redactionEvent.redacts])
            {
                NSLog(@"[MXEventTimeline] the current room state has been modified by the event redaction.");
                
                // Redact the stored event
                redactedEvent = [stateEvent prune];
                redactedEvent.redactedBecause = redactionEvent.JSONDictionary;
                
                [stateEvents replaceObjectAtIndex:index withObject:redactedEvent];
                
                // Reset the room state.
                _state = [[MXRoomState alloc] initWithRoomId:room.roomId andMatrixSession:room.mxSession andDirection:YES];
                [self initialiseState:stateEvents];
                
                // Update store with new room state when all state event have been processed
                if ([store respondsToSelector:@selector(storeStateForRoom:stateEvents:)])
                {
                    [store storeStateForRoom:_state.roomId stateEvents:_state.stateEvents];
                }
                
                // Reset the current pagination
                [self resetPagination];
                
                // Notify that room history has been flushed
                [[NSNotificationCenter defaultCenter] postNotificationName:kMXRoomDidFlushDataNotification
                                                                    object:room
                                                                  userInfo:nil];
                return;
            }
        }
    }
    
    // Re-sync the room in case of redacted state event from the past.
    // Indeed, redacted information shouldn't spontaneously appear when you backpaginate...
    if (!redactedEvent)
    {
        // Use a /context request to check whether the redacted event is a state event or not.
        httpOperation = [room.mxSession.matrixRestClient contextOfEvent:redactionEvent.redacts inRoom:room.roomId limit:1 success:^(MXEventContext *eventContext) {
            
            if (!httpOperation)
            {
                return;
            }
            httpOperation = nil;
            
            if (eventContext.event.isState)
            {
                NSLog(@"[MXEventTimeline] the redacted event is a state event from the past");
                [self forceRoomServerSync];
            }
            
        } failure:^(NSError *error) {
            
            if (!httpOperation)
            {
                return;
            }
            httpOperation = nil;
            
            NSLog(@"[MXEventTimeline] handleRedaction: failed to retrieved the redacted event");
            [self forceRoomServerSync];
        }];
    }
    else if (redactedEvent.isState)
    {
        NSLog(@"[MXEventTimeline] the redacted event is a former state event");
        [self forceRoomServerSync];
    }
}

- (void)forceRoomServerSync
{
    // Reset the storage of this room. Re-sync it from the server
    NSLog(@"[MXEventTimeline] re-sync room (%@) from the server.", room.roomId);
    [store deleteRoom:room.roomId];
    
    // Make an /initialSync request to get data
    // Use a 0 messages limit for now because:
    //    - /initialSync is marked as obsolete in the spec
    //    - MXEventTimeline does not have methods to handle /initialSync responses
    // So, avoid to write temparary code and let the user uses [MXEventTimeline paginate]
    // to get room messages.
    httpOperation = [room.mxSession.matrixRestClient initialSyncOfRoom:room.roomId withLimit:0 success:^(MXRoomInitialSync *roomInitialSync) {
        
        if (!httpOperation)
        {
            return;
        }
        httpOperation = nil;
        
        _state = [[MXRoomState alloc] initWithRoomId:room.roomId andMatrixSession:room.mxSession andDirection:YES];
        [self initialiseState:roomInitialSync.state];
        
        // Update store with new room state when all state event have been processed
        if ([store respondsToSelector:@selector(storeStateForRoom:stateEvents:)])
        {
            [store storeStateForRoom:_state.roomId stateEvents:_state.stateEvents];
        }
        
        [self resetPagination];
        
        // Notify that room history has been flushed
        [[NSNotificationCenter defaultCenter] postNotificationName:kMXRoomDidFlushDataNotification
                                                            object:room
                                                          userInfo:nil];
        
    } failure:^(NSError *error) {
        
        NSLog(@"[MXEventTimeline] forceRoomServerSync failed.");
        
        // Reload entirely the app
        [[NSNotificationCenter defaultCenter] postNotificationName:kMXSessionDidCorruptDataNotification
                                                            object:room.mxSession
                                                          userInfo:nil];
    }];
}

#pragma mark - State events handling
- (void)cloneState:(MXTimelineDirection)direction
{
    // create a new instance of the state
    if (MXTimelineDirectionBackwards == direction)
    {
        backState = [backState copy];
    }
    else
    {
        // Keep the previous state in cache for future usage in [self notifyListeners]
        previousState = _state;

        _state = [_state copy];
    }
}

- (void)handleStateEvent:(MXEvent*)event direction:(MXTimelineDirection)direction
{
    // Update the room state
    if (MXTimelineDirectionBackwards == direction)
    {
        [backState handleStateEvent:event];
    }
    else
    {
        // Forwards events update the current state of the room
        [_state handleStateEvent:event];

        // Special handling for presence: update MXUser data in case of membership event.
        // CAUTION: ignore here redacted state event, the redaction concerns only the context of the event room.
        if (_isLiveTimeline && MXEventTypeRoomMember == event.eventType && !event.isRedactedEvent)
        {
            MXUser *user = [room.mxSession getOrCreateUser:event.sender];

            MXRoomMember *roomMember = [_state memberWithUserId:event.sender];
            if (roomMember && MXMembershipJoin == roomMember.membership)
            {
                [user updateWithRoomMemberEvent:event roomMember:roomMember inMatrixSession:room.mxSession];

                [room.mxSession.store storeUser:user];
            }
        }
    }
}


#pragma mark - Events listeners
- (id)listenToEvents:(MXOnRoomEvent)onEvent
{
    return [self listenToEventsOfTypes:nil onEvent:onEvent];
}

- (id)listenToEventsOfTypes:(NSArray*)types onEvent:(MXOnRoomEvent)onEvent
{
    MXEventListener *listener = [[MXEventListener alloc] initWithSender:self andEventTypes:types andListenerBlock:onEvent];

    [eventListeners addObject:listener];

    return listener;
}

- (void)removeListener:(id)listener
{
    [eventListeners removeObject:listener];
}

- (void)removeAllListeners
{
    [eventListeners removeAllObjects];
}

- (void)notifyListeners:(MXEvent*)event direction:(MXTimelineDirection)direction
{
    MXRoomState * roomState;

    if (MXTimelineDirectionBackwards == direction)
    {
        roomState = backState;
    }
    else
    {
        if ([event isState])
        {
            // Provide the state of the room before this event
            roomState = previousState;
        }
        else
        {
            roomState = _state;
        }
    }

    // Notify all listeners
    // The SDK client may remove a listener while calling them by enumeration
    // So, use a copy of them
    NSArray *listeners = [eventListeners copy];

    for (MXEventListener *listener in listeners)
    {
        // And check the listener still exists before calling it
        if (NSNotFound != [eventListeners indexOfObject:listener])
        {
            [listener notify:event direction:direction andCustomObject:roomState];
        }
    }
    
    if (_isLiveTimeline && (direction == MXTimelineDirectionForwards))
    {
        // Check for local echo suppression
        if (room.outgoingMessages.count && [event.sender isEqualToString:room.mxSession.myUser.userId])
        {
            MXEvent *localEcho = [room pendingLocalEchoRelatedToEvent:event];
            if (localEcho)
            {
                // Remove the event from the pending local echo list
                [room removePendingLocalEcho:localEcho.eventId];
            }
        }
    }
}

@end
