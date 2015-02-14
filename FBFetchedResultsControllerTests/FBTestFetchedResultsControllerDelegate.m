/*
 *  Copyright (c) 2015, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

#import "FBTestFetchedResultsControllerDelegate.h"

@implementation FBTestFetchedResultsControllerDelegate
{
  NSMutableSet *_insertedObjects;
  NSMutableSet *_deletedObjects;
  NSMutableSet *_movedObjects;
  NSMutableSet *_updatedObjects;
}

- (instancetype)init
{
  if (self = [super init]) {
    _insertedObjects = [NSMutableSet set];
    _deletedObjects = [NSMutableSet set];
    _movedObjects = [NSMutableSet set];
    _updatedObjects = [NSMutableSet set];
  }
  return self;
}

- (void)controller:(FBFetchedResultsController *)controller
   didChangeObject:(id)anObject
       atIndexPath:(NSIndexPath *)indexPath
     forChangeType:(NSFetchedResultsChangeType)type
      newIndexPath:(NSIndexPath *)newIndexPath
{
  switch (type) {
    case NSFetchedResultsChangeInsert: [_insertedObjects addObject:anObject]; break;
    case NSFetchedResultsChangeDelete: [_deletedObjects addObject:anObject]; break;
    case NSFetchedResultsChangeMove: [_movedObjects addObject:anObject]; break;
    case NSFetchedResultsChangeUpdate: [_updatedObjects addObject:anObject]; break;
  }
}

- (NSSet *)insertedObjects { return _insertedObjects; }
- (NSSet *)deletedObjects { return _deletedObjects; }
- (NSSet *)movedObjects { return _movedObjects; }
- (NSSet *)updatedObjects { return _updatedObjects; }

@end
