/*
 *  Copyright (c) 2015, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant 
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

#import "FBModelHierarchyController.h"

/**
 @summary Methods on FBModelHierarchyController that control mutation of the models that are maintained by the receiver.
 */
@interface FBModelHierarchyController (Mutating)

/**
 @summary Adds an object to the receiver.

 @desc If the object is already in the arrangedObjects or does not
 pass the filterPredicate, this method has no effect.

 @param object The model object to add.
 */
- (void)addObject:(id)object;

/**
 @summary Adds an object to the receiver.

 @desc Adds the object to the model, skipping the filterPredicate check as a performance optimization where you know
 that the object passes the predicate.
 If the object is already in the arrangedObjects, this method has no effect.

 @param object The model object to add.
 */
- (void)addObjectUnfiltered:(id)object;

/**
 @summary Removes an object from the receiver.

 @desc If the object is not in the arrangedObjects, this method has no effect.

 @param object The model object to remove.
 */
- (void)removeObject:(id)object;

/**
 @summary Updates an object in the receiver.

 @desc This should be called after the model was updated by the external data source in order to notify the delegate.
 If the object moves as a result of this update, the delegate will be notified with a move change type rather than an
 update change type. If the object is not in the arrangedObjects
 and will not be added due to this update, this method has no effect.

 @param object The model object that was updated.
 */
- (void)updateObject:(id)object;

/**
 @summary Begins a batch update.

 @desc This method MUST be matched with a call to endUpdate.
 */
- (void)beginUpdate;

/**
 @summary Ends a batch update.

 @desc This method MUST be matched with a call to beginUpdate.
 */
- (void)endUpdate;

@end
