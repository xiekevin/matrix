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

#import <Foundation/Foundation.h>

#import "MXEventsEnumerator.h"

/**
 Generic events enumerator on an array of events with a filter on events types.
 */
@interface MXEventsByTypesEnumeratorOnArray : NSObject <MXEventsEnumerator>

/**
 Construct an enumerator based on a events array.

 @param messages the list of messages to enumerate on.
 @param types an array of event types strings to use as a filter filter.
 @param ignoreProfileChanges tell whether the profile changes should be ignored.

 @return the newly created instance.
 */
- (instancetype)initWithMessages:(NSArray<MXEvent*> *)messages andTypesIn:(NSArray*)types ignoreMemberProfileChanges:(BOOL)ignoreProfileChanges;

@end
