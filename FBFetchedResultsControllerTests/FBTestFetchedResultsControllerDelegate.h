/*
 *  Copyright (c) 2015, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

#import <Foundation/Foundation.h>

#import "FBFetchedResultsController.h"

@interface FBTestFetchedResultsControllerDelegate : NSObject <FBFetchedResultsControllerDelegate>
- (NSSet *)insertedObjects;
- (NSSet *)deletedObjects;
- (NSSet *)movedObjects;
- (NSSet *)updatedObjects;
@end
