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

#import "FBModelHierarchyController+Mutating.h"

#define FB_MODEL_HIERARCHY_CONTROLLER_START_STATE_CHANGE(change) do { \
if (change) { \
NSAssert(NO, @"attempt to change model list controller inside delegate/KVO"); \
} \
change = YES; \
} while (0)

#define FB_MODEL_HIERARCHY_CONTROLLER_END_STATE_CHANGE(change) do { \
if (!change) { \
NSAssert(NO, @"attempt to change model list controller inside delegate/KVO"); \
} \
change = NO; \
} while(0)

#define OBJECT_PASSES_FILTER(object__) ((_filterPredicate == nil) || [_filterPredicate evaluateWithObject:(object__)])

@interface FBModelHierarchySection : NSObject <FBModelHierarchySectionInfo, NSCopying>
- (instancetype)initWithName:(NSString *)name indexTitle:(NSString *)indexTitle;
@property (nonatomic, retain, readonly) NSMutableOrderedSet *objectSet;  // TODO: OrderedDictionary because we need to cmp pointers vs hashCode
@end

@interface FBModelHierarchySectionChange : NSObject
+ (instancetype)changeWithSection:(FBModelHierarchySection *)section
                            index:(NSUInteger)index
                       changeType:(FBModelChangeType)changeType;
@property (nonatomic, assign) FBModelChangeType changeType;
@property (nonatomic, assign) NSUInteger index;
@property (nonatomic, retain) FBModelHierarchySection *section;
@end

@interface FBModelHierarchyObjectChange : NSObject
+ (instancetype)changeWithSectionName:(NSString *)sectionName
                               object:(id)object
                            indexPath:(NSIndexPath *)indexPath
                           changeType:(FBModelChangeType)changeType;
@property (nonatomic, assign) FBModelChangeType changeType;
@property (nonatomic, retain) NSIndexPath *indexPath;
@property (nonatomic, retain) id object;
@property (nonatomic, copy) NSString *sectionName;
@end

@interface FBModelHierarchyPendingChanges : NSObject
@property (nonatomic, retain, readonly) NSSet *deletes;
@property (nonatomic, retain, readonly) NSSet *inserts;
@property (nonatomic, retain, readonly) NSOrderedSet *updates;
- (void)addChangeWithObject:(id)object changeType:(FBModelChangeType)changeType withIndexPath:(NSIndexPath *)indexPath;
- (NSIndexPath *)indexPathForObject:(id)object;
@end

@implementation FBModelHierarchySection
{
  NSString *_indexTitle;
  NSString *_name;
}
- (instancetype)initWithName:(NSString *)name indexTitle:(NSString *)indexTitle
{
  if ((self = [super init])) {
    _name = [name copy];
    _indexTitle = [indexTitle copy];
    _objectSet = [[NSMutableOrderedSet alloc] init];
  }
  return self;
}
- (instancetype)copyWithZone:(NSZone *)zone
{
  __typeof(self) copy = [[[self class] alloc] init];
  copy->_indexTitle = [_indexTitle copy];
  copy->_name = [_name copy];
  copy->_objectSet = [_objectSet mutableCopy];
  return copy;
}
- (NSString *)indexTitle
{
  return _indexTitle;
}
- (NSString *)name
{
  return _name;
}
- (NSUInteger)numberOfObjects
{
  return _objectSet.count;
}
- (NSArray *)objects
{
  return _objectSet.array;
}
- (NSUInteger)hash
{
  return [_name hash] ^ [_indexTitle hash];
}
- (BOOL)isEqual:(FBModelHierarchySection *)object
{
  if (self == object) {
    return YES;
  } else if (!object || ![object isKindOfClass:[FBModelHierarchySection class]]) {
    return NO;
  } else {
    return ((_name == nil && object->_name == nil) || [_name isEqual:object->_name])
    && ((_indexTitle == nil && object->_indexTitle == nil) || [_indexTitle isEqual:object->_indexTitle]);
  }
}
@end

@implementation FBModelHierarchySectionChange
+ (instancetype)changeWithSection:(FBModelHierarchySection *)section
                            index:(NSUInteger)index
                       changeType:(FBModelChangeType)changeType
{
  FBModelHierarchySectionChange *change = [[self alloc] init];
  change.section = section;
  change.index = index;
  change.changeType = changeType;
  return change;
}
@end

@implementation FBModelHierarchyObjectChange
+ (instancetype)changeWithSectionName:(NSString *)sectionName
                               object:(id)object
                            indexPath:(NSIndexPath *)indexPath
                           changeType:(FBModelChangeType)changeType
{
  FBModelHierarchyObjectChange *change = [[self alloc] init];
  change.sectionName = sectionName;
  change.object = object;
  change.indexPath = indexPath;
  change.changeType = changeType;
  return change;
}
@end

@implementation FBModelHierarchyPendingChanges
{
  NSMutableSet *_deletes;
  NSMutableSet *_inserts;
  NSMutableOrderedSet *_updates; // ordered by the original indexPath
  NSMapTable *_indexPathMap; // pointer equality for keys, and doesn't copy keys
}
- (instancetype)init
{
  if ((self = [super init])) {
    _deletes = [[NSMutableSet alloc] init];
    _inserts = [[NSMutableSet alloc] init];
    _updates = [[NSMutableOrderedSet alloc] init];

    _indexPathMap = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsObjectPointerPersonality
                                          valueOptions:0];
  }
  return self;
}
- (NSSet *)deletes
{
  return _deletes;
}
- (NSSet *)inserts
{
  return _inserts;
}
- (NSOrderedSet *)updates
{
  return _updates;
}
- (void)addChangeWithObject:(id)object changeType:(FBModelChangeType)changeType withIndexPath:(NSIndexPath*)indexPath
{
  NSAssert([NSObject instanceMethodForSelector:@selector(hash)]        == [[object class] instanceMethodForSelector:@selector(hash)] ||
           [NSManagedObject instanceMethodForSelector:@selector(hash)] == [[object class] instanceMethodForSelector:@selector(hash)],
           @"Implementation currently relies on the hashcode being mapped to the pointer.");
  switch (changeType) {
    case FBModelChangeTypeDelete:{
      NSAssert(indexPath != nil, @"Delete to existing object must contain indexPath");
      [_indexPathMap setObject:indexPath forKey:object];
      [_deletes addObject:object];
      break;
    }
    case FBModelChangeTypeInsert:{
      [_inserts addObject:object];
      break;
    }
    case FBModelChangeTypeMove:
    case FBModelChangeTypeUpdate:{
      if (![_updates containsObject:object]) {
        NSAssert(indexPath != nil, @"Update to existing object must contain indexPath");
        [_indexPathMap setObject:indexPath forKey:object];
        // sort all updates by their original indexPath
        NSUInteger destIndex = [_updates indexOfObject:object
                                         inSortedRange:NSMakeRange(0, [_updates count])
                                               options:NSBinarySearchingInsertionIndex
                                       usingComparator:^NSComparisonResult(id obj1, id obj2) {
                                         return [[self indexPathForObject:obj1] compare:[self indexPathForObject:obj2]];
                                       }];
        [_updates insertObject:object atIndex:destIndex];
      }
      break;
    }
  }
}
- (NSIndexPath *)indexPathForObject:(id)object
{
  return [_indexPathMap objectForKey:object];
}
@end

@interface FBModelHierarchyController ()
@property (nonatomic, retain) FBModelHierarchyPendingChanges *pendingChanges;
@property (nonatomic, retain) NSOrderedSet *sectionInfoSet;           // Set([name])  // sorted by sectionName
@property (nonatomic, retain) NSDictionary *sectionNameToSectionMap;  // name => section
@property (nonatomic, retain) FBModelHierarchySection *defaultSection;
@property (nonatomic) BOOL delegateWillChangeCallMade;
@end

@implementation FBModelHierarchyController
{
  BOOL _hasChange;
  NSUInteger _updateCounter;
  NSUInteger _duplicateInserts;
  NSComparator _sortComparator;
  NSArray * _memoizedArrangedObjects;
}

#pragma mark - Object Lifecycle

- (instancetype)initWithFilterPredicate:(NSPredicate *)filterPredicate
                        sortDescriptors:(NSArray *)sortDescriptors
                     sectionNameKeyPath:(NSString *)sectionNameKeyPath
{
  if ((self = [super init])) {
    _filterPredicate = [filterPredicate copy];
    _sortDescriptors = [sortDescriptors copy];
    _sectionNameKeyPath = [sectionNameKeyPath copy];
    if (_sectionNameKeyPath != nil) {
      _sectionNameToSectionMap = [NSMutableDictionary dictionary];
      if ([_sortDescriptors count] == 0) {
          _sortDescriptors = [NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:_sectionNameKeyPath ascending:YES]];
      }
    } else {
      _defaultSection = [[FBModelHierarchySection alloc] initWithName:nil indexTitle:nil];
    }
    _sortComparator = comparatorFromSortDescriptors(_sortDescriptors);
    _sectionInfoSet = [[NSMutableOrderedSet alloc] initWithObjects:_defaultSection, nil];
  }
  return self;
}

NSComparator comparatorFromSortDescriptors(NSArray *sortDescriptors)
{
  return [^NSComparisonResult(id obj1, id obj2) {
    for (NSSortDescriptor *sortDescriptor in sortDescriptors) {
      NSComparisonResult result = [sortDescriptor compareObject:obj1 toObject:obj2];
      if (result != NSOrderedSame) {
        return result;
      }
    }
    return NSOrderedSame;
  } copy];
}

#pragma mark - Model Accessors

- (NSArray *)arrangedObjects
{
  if (!_memoizedArrangedObjects) {
    /** We can just do a linear addition instead of an addition + sort because of this requirement in the docs:
     * "If the controller generates sections, the first sort descriptor in the array is used to group the objects into sections;
     * its key must either be the same as sectionNameKeyPath or the relative ordering using its key must match that using sectionNameKeyPath."
     */
    NSMutableArray *arrangedObjects = [[NSMutableArray alloc] init];
    for (FBModelHierarchySection *sectionInfo in _sectionInfoSet) {
      [arrangedObjects addObjectsFromArray:sectionInfo.objects];
    }
    _memoizedArrangedObjects = arrangedObjects;
  }
  return _memoizedArrangedObjects;
}

- (void)setSectionInfoSet:(NSOrderedSet *)sectionInfoSet
{
  _sectionInfoSet = sectionInfoSet;
  _memoizedArrangedObjects = nil; // wipe out cached value now that this changed
}

- (NSUInteger)countOfArrangedObjects
{
  NSUInteger count = 0;
  for (FBModelHierarchySection *sectionInfo in _sectionInfoSet) {
    count += sectionInfo.numberOfObjects;
  }
  return count;
}

- (NSIndexPath *)indexPathOfArrangedObject:(id)object
{
  return [self _indexPathOfObject:object
                 inSectionInfoSet:_sectionInfoSet
          sectionNameToSectionMap:_sectionNameToSectionMap];
}

- (id)objectInArrangedObjectsAtIndexPath:(NSIndexPath *)indexPath
{
  FBModelHierarchySection *sectionInfo = [_sectionInfoSet objectAtIndex:[indexPath indexAtPosition:0]];
  return [sectionInfo.objectSet objectAtIndex:[indexPath indexAtPosition:1]];
}

- (NSOrderedSet *)sections
{
  return _sectionInfoSet;
}

#pragma mark - Section Info

- (NSUInteger)countOfObjectsInSection:(NSUInteger)section
{
  FBModelHierarchySection *sectionInfo = [_sectionInfoSet objectAtIndex:section];
  return sectionInfo.objects.count;
}

- (NSArray *)objectsInSection:(NSUInteger)section
{
  FBModelHierarchySection *sectionInfo = [_sectionInfoSet objectAtIndex:section];
  return sectionInfo.objects;
}

#pragma mark - Helper Methods

- (void)_makeWillChangeDelegateCallIfNecessary
{
  if (!self.delegateWillChangeCallMade) {
    [_delegate modelHierarchyControllerWillChangeContent:self];
    self.delegateWillChangeCallMade = YES;
  }
}


- (BOOL)_deleteObject:(id)object
     inSectionInfoSet:(NSMutableOrderedSet *)sectionInfoSet
sectionNameToSectionMap:(NSMutableDictionary *)sectionNameToSectionMap
            indexPath:(NSIndexPath *)indexPath
      affectedSection:(FBModelHierarchySection **)affectedSectionRef
         objectChange:(FBModelHierarchyObjectChange **)objectChangeRef
{
  FBModelHierarchySection *sectionInfo = [self _sectionInfoForObject:object
                                                    inSectionInfoSet:sectionInfoSet
                                             sectionNameToSectionMap:sectionNameToSectionMap];
  if (sectionInfo == nil) {
    NSAssert(NO, @"Deletes require an existing object");
    if (objectChangeRef != NULL) {
      *objectChangeRef = nil;
    }
    return NO;
  }

  [sectionInfo.objectSet removeObject:object];
  if (affectedSectionRef != NULL) {
    *affectedSectionRef = sectionInfo;
  }
  if (objectChangeRef != NULL) {
    *objectChangeRef = [FBModelHierarchyObjectChange changeWithSectionName:sectionInfo.name
                                                                    object:object
                                                                 indexPath:indexPath
                                                                changeType:FBModelChangeTypeDelete];
  }
  return YES;
}

- (FBModelHierarchySection *)_ensureSectionInfoForObject:(id)object
                                        inSectionInfoSet:(NSMutableOrderedSet *)sectionInfoSet
                                 sectionNameToSectionMap:(NSMutableDictionary *)sectionNameToSectionMap
                                           sectionChange:(FBModelHierarchySectionChange **)sectionChangeRef
{
  // fast path, when ensuring the section, it must match the current section name on the object
  NSString *sectionName = nil; // default = flat heirarchy
  if (_sectionNameKeyPath) {
    sectionName = [[object valueForKeyPath:_sectionNameKeyPath] description];
    // nil indicates invalid keypath (e.g. deleted edge relationship), we need to filter out these
    if (sectionName == nil) {
      if (sectionChangeRef != NULL) *sectionChangeRef = nil;
      return nil;
    }
  }
  id sectionKey = sectionName ?: [NSNull null];

  // fast path, look for the section based on the section name
  FBModelHierarchySection *sectionInfo = sectionNameToSectionMap[sectionKey];
  if (sectionInfo != nil) {
    if (sectionChangeRef != NULL)  { *sectionChangeRef = nil; }
    return sectionInfo;
  }

  // not found, create it
  NSString *sectionIndexTitle = [_delegate modelHierarchyController:self sectionIndexTitleForSectionName:sectionName];
  sectionInfo = [[FBModelHierarchySection alloc] initWithName:sectionName indexTitle:sectionIndexTitle];
  sectionNameToSectionMap[sectionKey] = sectionInfo;
  // append the new section now, we'll sort it later because we need to verify all sections in this set have an entity
  [sectionInfoSet insertObject:sectionInfo atIndex:sectionInfoSet.count];
  if (sectionChangeRef != NULL) {
    *sectionChangeRef = [FBModelHierarchySectionChange changeWithSection:sectionInfo
                                                                   index:NSNotFound
                                                              changeType:FBModelChangeTypeInsert];
  }
  return sectionInfo;
}

- (NSIndexPath *)_indexPathOfObject:(id)object
                   inSectionInfoSet:(NSOrderedSet *)sectionInfoSet
            sectionNameToSectionMap:(NSDictionary *)sectionNameToSectionMap
{
  FBModelHierarchySection *sectionInfo = [self _sectionInfoForObject:object
                                                    inSectionInfoSet:sectionInfoSet
                                             sectionNameToSectionMap:sectionNameToSectionMap];
  if (sectionInfo == nil) {
    return nil;
  }

  NSUInteger sectionIndex = [sectionInfoSet indexOfObject:sectionInfo];
  NSUInteger row = [sectionInfo.objectSet indexOfObject:object];
  if (row == NSNotFound) {
    return nil;
  }

  NSUInteger indexes[] = {sectionIndex, row};
  return [NSIndexPath indexPathWithIndexes:indexes length:2];
}

- (NSIndexPath *)_insertObject:(id)object
              inSectionInfoSet:(NSMutableOrderedSet *)sectionInfoSet
       sectionNameToSectionMap:(NSMutableDictionary *)sectionNameToSectionMap
                 sectionChange:(FBModelHierarchySectionChange **)sectionChangeRef
                  objectChange:(FBModelHierarchyObjectChange **)objectChangeRef
{
  // find/create the section
  FBModelHierarchySection *sectionInfo = [self _ensureSectionInfoForObject:object
                                                          inSectionInfoSet:sectionInfoSet
                                                   sectionNameToSectionMap:sectionNameToSectionMap
                                                             sectionChange:sectionChangeRef];
  if (!sectionInfo) {
    return nil;
  }
  // add the new object into its appropriate section
  NSMutableOrderedSet *sectionObjectSet = sectionInfo.objectSet;
  if ([sectionObjectSet containsObject:object]) {
    NSAssert(NO, @"Tried to double-insert a %@ object", [object class]);
    return nil;
  }
  NSUInteger destinationIndex = [sectionObjectSet indexOfObject:object
                                                  inSortedRange:NSMakeRange(0, [sectionObjectSet count])
                                                        options:NSBinarySearchingInsertionIndex
                                                usingComparator:_sortComparator];
  [sectionObjectSet insertObject:object atIndex:destinationIndex];
  NSIndexPath *indexPath = [self _indexPathOfObject:object
                                   inSectionInfoSet:sectionInfoSet
                            sectionNameToSectionMap:sectionNameToSectionMap];

  if (objectChangeRef != NULL) {
    *objectChangeRef = [FBModelHierarchyObjectChange changeWithSectionName:sectionInfo.name
                                                                    object:object
                                                                 indexPath:nil
                                                                changeType:FBModelChangeTypeInsert];
  }

  return indexPath;
}

- (void)_processPendingChanges:(FBModelHierarchyPendingChanges *)pendingChanges
{
  // make a deep copy of the sectionInfoSet, as we will be modifying the section objects for the new hierarchy data
  NSMutableOrderedSet *newSectionInfoSet = [NSMutableOrderedSet orderedSetWithOrderedSet:_sectionInfoSet range:NSMakeRange(0, [_sectionInfoSet count]) copyItems:YES];

  NSMutableDictionary *newSectionNameToSectionMap = [NSMutableDictionary dictionary];
  for (FBModelHierarchySection *section in newSectionInfoSet) {
    newSectionNameToSectionMap[section.name ?: [NSNull null]] = section;
  }

  // these sets will hold all of the changes that we apply to the new data - after processing the data we can notify
  // the delegate, when we know the destination indexPaths as well
  NSMutableSet *sectionChangeSet = [[NSMutableSet alloc] init];
  NSMutableSet *objectChangeSet = [[NSMutableSet alloc] init];
  NSMutableSet *possibleEmptySections = [NSMutableSet set];

  // loop through the deletes and remove them from the new data
  for (id object in pendingChanges.deletes) {
    NSIndexPath *originalIndexPath = [pendingChanges indexPathForObject:object];
    FBModelHierarchySection *section = nil;
    FBModelHierarchyObjectChange *objectChange = nil;
    if (![self _deleteObject:object
            inSectionInfoSet:newSectionInfoSet
     sectionNameToSectionMap:newSectionNameToSectionMap
                   indexPath:originalIndexPath
             affectedSection:&section
                objectChange:&objectChange]) {
      // already asserted - continue
      continue;
    }

    // store the change to notify after we know what we can suppress with section deletes
    [objectChangeSet addObject:objectChange];
    [possibleEmptySections addObject:section];
  }

  // loop through the updates.  they should be removed/reinserted to guarantee the section is sorted
  // first pass: remove all objects in descending order to retain original fromIndexPath
  NSMutableDictionary *originalInfoForUpdate = [NSMutableDictionary dictionary];
  for (id object in pendingChanges.updates.reverseObjectEnumerator) {
    FBModelHierarchySection *section = nil;
    FBModelHierarchyObjectChange *objectDeletion = nil;
    // the original indexPath of this object before any pending changes were applied
    NSIndexPath *originalIndexPath = [pendingChanges indexPathForObject:object];
    // capture the indexPath just before we perform any model alterations
    // this is used to determine if we've performed a relative (vs absolute) index move
    NSIndexPath *fromIndexPath = [self _indexPathOfObject:object
                                         inSectionInfoSet:newSectionInfoSet
                                  sectionNameToSectionMap:newSectionNameToSectionMap];
    // delete the object from the model first, we may not reinsert it
    if (![self _deleteObject:object
            inSectionInfoSet:newSectionInfoSet
     sectionNameToSectionMap:newSectionNameToSectionMap
                   indexPath:originalIndexPath
             affectedSection:&section
                objectChange:&objectDeletion]) {
      // object didn't exist to begin with (possibly because we did a delete + update for the same object within the transaction)
      continue;
    }
    // section moves or deletes could create an empty section. unconditionally check
    [possibleEmptySections addObject:section];
    // save critical state about this update for the next loop
    NSValue *updateMapKey = [NSValue valueWithPointer:(__bridge const void *)(object)];
    originalInfoForUpdate[updateMapKey] = @[fromIndexPath, objectDeletion ?: [NSNull null]];
  }
  // second pass: reinsert objects in ascending order so we can track relative moves
  for (id object in pendingChanges.updates.objectEnumerator) {
    NSValue *updateMapKey = [NSValue valueWithPointer:(__bridge const void *)(object)];
    NSIndexPath *fromIndexPath = originalInfoForUpdate[updateMapKey][0];
    FBModelHierarchyObjectChange *objectDeletion = originalInfoForUpdate[updateMapKey][1];

    // re-insert the object - this time capture the change, which we will modify afterwards
    FBModelHierarchySectionChange *sectionChange = nil;
    FBModelHierarchyObjectChange *objectChange = nil;
    NSIndexPath *toIndexPath = [self _insertObject:object
                                  inSectionInfoSet:newSectionInfoSet
                           sectionNameToSectionMap:newSectionNameToSectionMap
                                     sectionChange:&sectionChange
                                      objectChange:&objectChange];
    if (toIndexPath == nil) {
      // updates with no indexPath become a deletion (e.g. an edge in the keypath is removed)
      if ((id)objectDeletion == [NSNull null]) {
        NSAssert(NO, @"Tried to delete object on update without change information: %@", object);
      } else {
        [objectChangeSet addObject:objectDeletion];
      }
      continue;
    }

    // set the original indexPath for the object on the change
    objectChange.indexPath = [pendingChanges indexPathForObject:object];
    // first check: decide if this is a update or move based upon relative index path change
    // TODO(#2925781) we could be more intelligent about determining move vs update
    objectChange.changeType = ([fromIndexPath isEqual:toIndexPath]) ? FBModelChangeTypeUpdate : FBModelChangeTypeMove;

    if (sectionChange != nil) {
      [sectionChangeSet addObject:sectionChange];
    }
    if (objectChange != nil) {
      [objectChangeSet addObject:objectChange];
    }
  }

  // similar to the updates, we need to do the inserts and defer the notifications until we have the final indexPaths
  for (id object in pendingChanges.inserts) {
    FBModelHierarchySectionChange *sectionChange = nil;
    FBModelHierarchyObjectChange *objectChange = nil;
    [self _insertObject:object
       inSectionInfoSet:newSectionInfoSet
sectionNameToSectionMap:newSectionNameToSectionMap
          sectionChange:&sectionChange
           objectChange:&objectChange];
    if (sectionChange != nil) {
      [sectionChangeSet addObject:sectionChange];
    }
    if (objectChange != nil) {
      [objectChangeSet addObject:objectChange];
    }
  }

  // look for empty sections and delete them
  for (FBModelHierarchySection *sectionInfo in possibleEmptySections) {
    if (sectionInfo.objects.count == 0 && ![sectionInfo isEqual:_defaultSection]) {
      // We want to look up the original index of the section, so use _sectionInfoSet, not our modified local copy.
      NSUInteger originalSectionIndex = [_sectionInfoSet indexOfObject:sectionInfo];
      NSAssert(originalSectionIndex != NSNotFound, @"Expected to find sectionInfo in _sectionInfoSet");
      [sectionChangeSet addObject:[FBModelHierarchySectionChange changeWithSection:sectionInfo
                                                                             index:originalSectionIndex
                                                                        changeType:FBModelChangeTypeDelete]];
      id sectionName = sectionInfo.name ?: [NSNull null];
      [newSectionNameToSectionMap removeObjectForKey:sectionName];
      [newSectionInfoSet removeObject:sectionInfo];
    }
  }

  // shuffle new sections into the proper slot now that all empty sections have been reaped
  for (FBModelHierarchySectionChange *sectionChange in sectionChangeSet) {
    if (sectionChange.changeType == FBModelChangeTypeInsert) {
      [newSectionInfoSet removeObject:sectionChange.section];
    }
  }
  for (FBModelHierarchySectionChange *sectionChange in sectionChangeSet) {
    if (sectionChange.changeType == FBModelChangeTypeInsert) {
      NSUInteger dest = [newSectionInfoSet indexOfObject:sectionChange.section
                                           inSortedRange:NSMakeRange(0, [newSectionInfoSet count])
                                                 options:NSBinarySearchingInsertionIndex
                                         usingComparator:^NSComparisonResult(FBModelHierarchySection *left, FBModelHierarchySection *right) {
                                        NSAssert(left.objectSet.firstObject && right.objectSet.firstObject, @"Section contents necessary for sorting");
                                        return _sortComparator(left.objectSet.firstObject, right.objectSet.firstObject);
                                      }];
      NSAssert(dest != NSNotFound, @"Could not find InsertionIndex for new section");
      [newSectionInfoSet insertObject:sectionChange.section atIndex:dest];
    }
  }

  // notify the delegate of all of the section change inserts
  for (FBModelHierarchySectionChange *sectionChange in sectionChangeSet) {
    if (sectionChange.changeType == FBModelChangeTypeInsert) {
      id sectionName = sectionChange.section.name ?: [NSNull null];
      sectionChange.index = [newSectionInfoSet indexOfObject:newSectionNameToSectionMap[sectionName]];
      [self _makeWillChangeDelegateCallIfNecessary];
      [_delegate modelHierarchyController:self
                         didChangeSection:sectionChange.section
                                  atIndex:sectionChange.index
                            forChangeType:sectionChange.changeType];
    } else {
      // Moves/updates are invalid for section changes
      NSAssert(sectionChange.changeType == FBModelChangeTypeDelete, @"Invalid change type for section change");
    }
  }

  // notify the delegate of all of the object changes
  for (FBModelHierarchyObjectChange *objectChange in objectChangeSet) {
    NSIndexPath *newIndexPath = nil;
    switch (objectChange.changeType) {
      case FBModelChangeTypeInsert:{
        // we need the new indexPath for these change types, after all of the changes are applied
        newIndexPath = [self _indexPathOfObject:objectChange.object
                               inSectionInfoSet:newSectionInfoSet
                        sectionNameToSectionMap:newSectionNameToSectionMap];
        break;
      }

      case FBModelChangeTypeMove:
      case FBModelChangeTypeUpdate:{
        // only give the new indexPath changed from the old path (e.g. object before us was removed)
        newIndexPath = [self _indexPathOfObject:objectChange.object
                               inSectionInfoSet:newSectionInfoSet
                        sectionNameToSectionMap:newSectionNameToSectionMap];
        // we've already performed a relative path check, now use absolute path comparison to determine if a move
        if (![objectChange.indexPath isEqual:newIndexPath]) {
          objectChange.changeType = FBModelChangeTypeMove;
        }
        break;
      }
      case FBModelChangeTypeDelete:{
        // a new indexPath is not relevant for deletes
        break;
      }
    }
    [self _makeWillChangeDelegateCallIfNecessary];
    [_delegate modelHierarchyController:self
                        didChangeObject:objectChange.object
                            atIndexPath:objectChange.indexPath
                          forChangeType:objectChange.changeType
                           newIndexPath:newIndexPath];
  }

  // notify the delegate of all the section deletes
  for (FBModelHierarchySectionChange *sectionChange in sectionChangeSet) {
    if (sectionChange.changeType == FBModelChangeTypeDelete) {
      // index already represents the old index
      [self _makeWillChangeDelegateCallIfNecessary];
      [_delegate modelHierarchyController:self
                         didChangeSection:sectionChange.section
                                  atIndex:sectionChange.index
                            forChangeType:sectionChange.changeType];
    } else {
      // Moves/updates are invalid for section changes
      NSAssert(sectionChange.changeType == FBModelChangeTypeInsert, @"Invalid change type for section change");
    }
  }

  self.sectionInfoSet = newSectionInfoSet;
  self.sectionNameToSectionMap = newSectionNameToSectionMap;
}

- (FBModelHierarchySection *)_sectionInfoForObject:(id)object
                                  inSectionInfoSet:(NSOrderedSet *)sectionInfoSet
                           sectionNameToSectionMap:(NSDictionary *)sectionNameToSectionMap
{
  FBModelHierarchySection *sectionInfo;

  // fast path, look for the section based on the current section name from the object
  if (_sectionNameKeyPath) {
    NSString *sectionName = [[object valueForKeyPath:_sectionNameKeyPath] description];
    if (sectionName) {
      sectionInfo = sectionNameToSectionMap[sectionName];
      if ([sectionInfo.objectSet containsObject:object]) {
        return sectionInfo;
      }
    }
  }

  // slow path, look through the sections sequentially until we find the object or reach the end
  // (this is needed in case the object has changed since added to the section - the name may not match the current section)
  for (sectionInfo in sectionInfoSet) {
    if ([sectionInfo.objectSet containsObject:object]) {
      return sectionInfo;
    }
  }

  return nil;
}

@end

#pragma mark - Mutating Category

@implementation FBModelHierarchyController (Private)

- (void)addObjectUnfiltered:(id)object
{
  FB_MODEL_HIERARCHY_CONTROLLER_START_STATE_CHANGE(_hasChange);
  [self beginUpdate];
  NSAssert(_pendingChanges != nil, @"Unexpected change outside of a batch");
  // try to find the object in the existing MHC
  NSIndexPath * indexPath = [self _indexPathOfObject:object inSectionInfoSet:_sectionInfoSet sectionNameToSectionMap:_sectionNameToSectionMap];
  if (indexPath == nil) {
    // this is a new object, insert
    [_pendingChanges addChangeWithObject:object changeType:FBModelChangeTypeInsert withIndexPath:nil];
  } else {
    // treat as an update, even though this is technically incorrect.
    [_pendingChanges addChangeWithObject:object changeType:FBModelChangeTypeUpdate withIndexPath:indexPath];
    _duplicateInserts++;
  }
  [self endUpdate];
  FB_MODEL_HIERARCHY_CONTROLLER_END_STATE_CHANGE(_hasChange);
}

- (void)addObject:(id)object
{
  if (!OBJECT_PASSES_FILTER(object)) {
    return;
  }
  [self addObjectUnfiltered:object];
}

- (void)removeObject:(id)object
{
  NSIndexPath *indexPath = [self _indexPathOfObject:object
                                   inSectionInfoSet:_sectionInfoSet
                            sectionNameToSectionMap:_sectionNameToSectionMap];
  if (indexPath == nil) {
    return;
  }

  FB_MODEL_HIERARCHY_CONTROLLER_START_STATE_CHANGE(_hasChange);
  [self beginUpdate];
  NSAssert(_pendingChanges != nil, @"Unexpected change outside of a batch");
  [_pendingChanges addChangeWithObject:object changeType:FBModelChangeTypeDelete withIndexPath:indexPath];
  [self endUpdate];
  FB_MODEL_HIERARCHY_CONTROLLER_END_STATE_CHANGE(_hasChange);
}

- (void)updateObject:(id)object
{
  // find the current position
  NSIndexPath *indexPath = [self _indexPathOfObject:object
                                   inSectionInfoSet:_sectionInfoSet
                            sectionNameToSectionMap:_sectionNameToSectionMap];
  if (OBJECT_PASSES_FILTER(object)) {
    // we need to add the object if it doesn't exist (possibly from filtering)
    if (indexPath == nil) {
      [self addObject:object];
      return;
    }
  } else {
    // if it's filtered out, stop here and remove if present
    if (indexPath != nil) {
      [self removeObject:object];
    }
    return;
  }

  FB_MODEL_HIERARCHY_CONTROLLER_START_STATE_CHANGE(_hasChange);
  [self beginUpdate];
  NSAssert(_pendingChanges != nil, @"Unexpected change outside of a batch");
  [_pendingChanges addChangeWithObject:object changeType:FBModelChangeTypeUpdate withIndexPath:indexPath];
  [self endUpdate];
  FB_MODEL_HIERARCHY_CONTROLLER_END_STATE_CHANGE(_hasChange);
}

- (void)beginUpdate
{
  _updateCounter += 1;
  if (_updateCounter == 1) {
    NSAssert(_pendingChanges == nil, @"There should be no pending changes when the update batch begins");
    FBModelHierarchyPendingChanges *pendingChanges = [[FBModelHierarchyPendingChanges alloc] init];
    self.pendingChanges = pendingChanges;
    [_delegate modelHierarchyControllerWillChangeContent:self];
    _delegateWillChangeCallMade = YES;
  }
}

- (void)endUpdate
{
  if (_updateCounter == 0) {
    NSAssert(NO, @"Mismatched begin/end update calls");
    return;
  }

  _updateCounter -= 1;
  if (_updateCounter == 0) {
    FBModelHierarchyPendingChanges *pendingChanges = _pendingChanges;
    self.pendingChanges = nil;
    [self _processPendingChanges:pendingChanges];
    // Only call "didChange" if "willChange" was called ever.
    if (self.delegateWillChangeCallMade) {
      [_delegate modelHierarchyControllerDidChangeContent:self];
      self.delegateWillChangeCallMade = NO;
    }
    if (_duplicateInserts > 0) {
      _duplicateInserts = 0;
    }
  }
}

@end
