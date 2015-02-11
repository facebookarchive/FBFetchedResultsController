/*
 *  Copyright (c) 2015, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant 
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

#import "FBFetchedResultsController.h"

#import "FBModelHierarchyController+Mutating.h"
#import "FBModelHierarchyController.h"

@interface FBFetchedResultsController () <FBModelHierarchyControllerDelegate>
{
  BOOL _registeredForNotifications;
}
@property (nonatomic, strong) FBModelHierarchyController *dataController;
@property (nonatomic, strong) NSEntityDescription *fetchedEntity; // the type of Managed Object being grouped
@property (nonatomic, strong) NSMutableSet *insertedObjectsInFlux; // New Managed Objects that were fetched but will trigger a notification upon save
@end

@implementation FBFetchedResultsController

#pragma mark - Lifecycle

static NSHashTable *allFetchedResultsControllers; // weak

- (instancetype)initWithFetchRequest:(NSFetchRequest *)fetchRequest
                managedObjectContext:(NSManagedObjectContext *)managedObjectContext
                  sectionNameKeyPath:(NSString *)sectionNameKeyPath
                           cacheName:(NSString *)cacheName
          {
  if ((self = [super init])) {
    _fetchRequest = fetchRequest;
    _managedObjectContext = managedObjectContext;
    _sectionNameKeyPath = [sectionNameKeyPath copy];
    _cacheName = [cacheName copy];
    _insertedObjectsInFlux = [[NSMutableSet alloc] init];

    /*
     * NSFRC has three modes of operation:
     * 1. No tracking : provide access to the data when fetch is executed
     * 2. Memory-only tracking : monitors MOC changes and updates accordingly
     * 3. Full persistent tracking : Same as #2, but also persist cache for restarts
     *
     * We currently only support #1 & #2
     */

    @synchronized([FBFetchedResultsController class]) {
      if (allFetchedResultsControllers == nil) {
        allFetchedResultsControllers = [NSHashTable weakObjectsHashTable];
      }
      [allFetchedResultsControllers addObject:self];
    }
  }
  return self;
}

- (void)dealloc
{
  // note: technically not safe, dealloc runs on an undefined thread
  [[NSNotificationCenter defaultCenter] removeObserver:self];

  _dataController.delegate = nil;
}

#pragma mark - Did Merge Notifications

+ (void)didMergeChangesFromContextDidSaveNotification:(NSNotification *)notification
                                          intoContext:(NSManagedObjectContext *)context
{
  NSArray *frcs;
  @synchronized([FBFetchedResultsController class]) {
    frcs = [allFetchedResultsControllers allObjects];
  }
  for (FBFetchedResultsController *frc in frcs) {
    if (frc->_managedObjectContext == context && frc->_registeredForNotifications) {
      [frc _handleManagedObjectContextMergeNotification:notification];
    }
  }
}

#pragma mark - Class Methods

+ (void)deleteCacheWithName:(NSString *)name
{
  // cache not supported - noop
}

#pragma mark - Properties

- (NSArray *)fetchedObjects
{
  return _dataController.arrangedObjects;
}

- (NSArray *)sections
{
  return _dataController.sections.array;
}

// DOCS: The default implementation returns the array created by calling sectionIndexTitleForSectionName: on all the known sections. You should override this method if you want to return a different array for the section index.
- (NSArray *)sectionIndexTitles
{
  NSOrderedSet * ret = [_dataController.sections valueForKey:@"indexTitle"]; // this needs to be NSSet to remove nil values
  return ret.array;
}

#pragma mark - Data Access

- (NSIndexPath *)indexPathForObject:(id)object
{
  return [_dataController indexPathOfArrangedObject:object];
}

- (id)objectAtIndexPath:(NSIndexPath *)indexPath
{
  return [_dataController objectInArrangedObjectsAtIndexPath:indexPath];
}

- (NSInteger)sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)sectionIndex
{
  // rarely used function.  sanity checks that the section index is consistent with what you expect
  id<NSFetchedResultsSectionInfo> section = [_dataController.sections objectAtIndex:sectionIndex];
  if (section == nil) {
    [NSException raise:NSInternalInconsistencyException format:@"invalid Section Index offset: %zd", sectionIndex];
  } else if(![[[section indexTitle] description] isEqualToString:title]) {
    [NSException raise:NSInternalInconsistencyException format:@"Index title at %zd is not equal to %@", sectionIndex, title];
  } else {
    return sectionIndex;
  }
  return -1;
}

- (NSString *)sectionIndexTitleForSectionName:(NSString *)sectionName
{
  return ([sectionName length] > 0) ? [[sectionName substringToIndex:1] capitalizedString] : nil;
}

#pragma mark - Actions

- (BOOL)performFetch:(NSError **)error
{
  // clear the delegate so we stop processing anything with that data controller
  _dataController.delegate = nil;

  self.fetchedEntity = _fetchRequest.entity;
  NSArray *fetchedObjectsFiltered = [_managedObjectContext executeFetchRequest:_fetchRequest error:error];
  if (fetchedObjectsFiltered == nil) {
    self.dataController = nil;
    return NO;
  }

  FBModelHierarchyController *dataController = [[FBModelHierarchyController alloc] initWithFilterPredicate:_fetchRequest.predicate
                                                                                           sortDescriptors:_fetchRequest.sortDescriptors
                                                                                        sectionNameKeyPath:_sectionNameKeyPath];
  dataController.delegate = self;
  [dataController beginUpdate];
  for (NSManagedObject *object in fetchedObjectsFiltered) {
    [dataController addObjectUnfiltered:object];
    if ([object isInserted]) { [_insertedObjectsInFlux addObject:object]; }
  }
  [dataController endUpdate];
  self.dataController = dataController; // assign here so we don't notify our delegates about the above updates

  if ([self _changeTrackingEnabled]) {
    if (!_registeredForNotifications) {
      NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
      [nc addObserver:self
             selector:@selector(_handleManagedObjectContextSaveNotification:)
                 name:NSManagedObjectContextDidSaveNotification
               object:_managedObjectContext];
      _registeredForNotifications = YES;
    }
  } else {
    if (_registeredForNotifications) {
      NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
      [nc removeObserver:self name:NSManagedObjectContextDidSaveNotification object:_managedObjectContext];
      _registeredForNotifications = NO;
    }
  }

  return YES;
}

#pragma mark - Notification Handlers

/**
 * From Apple Docs...
 *
 * Important: A delegate must implement at least one of the change tracking delegate methods in order for change tracking to be enabled. Providing an empty implementation of controllerDidChangeContent: is sufficient.
 */
- (BOOL)_changeTrackingEnabled
{
  return _delegate && ([_delegate respondsToSelector:@selector(controllerDidChangeContent:)] ||
                       [_delegate respondsToSelector:@selector(controllerWillChangeContent:)] ||
                       [_delegate respondsToSelector:@selector(controller:didChangeSection:atIndex:forChangeType:)] ||
                       [_delegate respondsToSelector:@selector(controller:didChangeObject:atIndexPath:forChangeType:newIndexPath:)]);
}

- (void)_handleManagedObjectContextMergeNotification:(NSNotification *)notification
{
  // the merge notification comes with a userInfo dictionary built from a save notification from a different MOC
  // so the models are not safely usable on this thread - fetch new ones
  NSMutableDictionary *newUserInfo = [NSMutableDictionary dictionary];
  for (NSString *key in @[NSDeletedObjectsKey, NSRefreshedObjectsKey, NSUpdatedObjectsKey, NSInsertedObjectsKey]) {
    NSMutableSet *objects = [NSMutableSet set];
    for (NSManagedObjectID *objectID in [notification.userInfo[key] valueForKey:@"objectID"]) {
      id obj = [_managedObjectContext objectWithID:objectID];
      if (nil != obj) {
        [objects addObject:obj];
      }
    }
    newUserInfo[key] = objects;
  }
  [self _processMocChanges:newUserInfo];
}

- (void)_handleManagedObjectContextSaveNotification:(NSNotification *)notification
{
  NSAssert(notification.object == _managedObjectContext, nil);
  [self _processMocChanges:notification.userInfo];
}

- (void)_processMocChanges:(NSDictionary*)userInfo
{
  // this MOC save may have a bunch of entity that we don't care about, filter out the changes to only the entity we're using
  // NOTE: we currently don't handle changes to related entities in the sectionNameKeypath
  NSMutableDictionary *keyToObjectsMap = [NSMutableDictionary dictionary];
  for (NSString *key in @[NSDeletedObjectsKey, NSInsertedObjectsKey, NSRefreshedObjectsKey, NSUpdatedObjectsKey]) {
    NSMutableSet *objects = [NSMutableSet set];
    for (NSManagedObject *object in userInfo[key]) {
      if ([object.entity isKindOfEntity:_fetchedEntity]) {
        [objects addObject:object];
      }
    }
    if ([objects count]) {
      keyToObjectsMap[key] = objects;
    }
  }

  // NOTE: if we are storing entity B, accessed via a A.filter()->B.filter() query, make sure that still holds

  // if we have pertinent data to transform
  if ([keyToObjectsMap count]) {
    [_dataController beginUpdate];

    for (NSManagedObject *object in keyToObjectsMap[NSDeletedObjectsKey]) {
      [_dataController removeObject:object];
    }

    for (NSManagedObject *object in keyToObjectsMap[NSInsertedObjectsKey]) {
      if ([_insertedObjectsInFlux containsObject:object]) {
        [_dataController updateObject:object];
        [_insertedObjectsInFlux removeObject:object];
        if ([_insertedObjectsInFlux count] == 0) self.insertedObjectsInFlux = nil;
      } else {
        [_dataController addObject:object];
      }
    }

    for (NSString *key in @[NSRefreshedObjectsKey, NSUpdatedObjectsKey]) {
      for (NSManagedObject *object in keyToObjectsMap[key]) {
        [_dataController updateObject:object];
      }
    }

    [_dataController endUpdate];
  }
}

#pragma mark - FBModelHierarchyControllerDelegate

// when fetching data, we have set the delegate, but we don't want to forward the messages - check that it is the ivar
// value before forwarding the delegate messages
#define CHECK_DATA_CONTROLLER(dataController__) ((_dataController != nil) && ((dataController__) == _dataController))

- (void)modelHierarchyController:(FBModelHierarchyController *)modelHierarchyController
                 didChangeObject:(id)object
                     atIndexPath:(NSIndexPath *)indexPath
                   forChangeType:(FBModelChangeType)changeType
                    newIndexPath:(NSIndexPath *)newIndexPath
{
  if (!CHECK_DATA_CONTROLLER(modelHierarchyController)) { return; }
  if ([_delegate respondsToSelector:@selector(controller:didChangeObject:atIndexPath:forChangeType:newIndexPath:)]) {
    [_delegate controller:self
          didChangeObject:object
              atIndexPath:indexPath
            forChangeType:(NSFetchedResultsChangeType)changeType
             newIndexPath:newIndexPath];
  }
}

- (void)modelHierarchyController:(FBModelHierarchyController *)modelHierarchyController
                didChangeSection:(id<FBModelHierarchySectionInfo>)section
                         atIndex:(NSUInteger)index
                   forChangeType:(FBModelChangeType)changeType
{
  if (!CHECK_DATA_CONTROLLER(modelHierarchyController)) { return; }
  if ([_delegate respondsToSelector:@selector(controller:didChangeSection:atIndex:forChangeType:)]) {
    [_delegate controller:self didChangeSection:section atIndex:index forChangeType:(NSFetchedResultsChangeType)changeType];
  }
}


- (NSString *)modelHierarchyController:(FBModelHierarchyController *)modelHierarchyController
       sectionIndexTitleForSectionName:(NSString *)sectionName
{
  if([_delegate respondsToSelector:@selector(controller:sectionIndexTitleForSectionName:)]) {
    return [_delegate controller:self sectionIndexTitleForSectionName:sectionName];
  } else {
    return [self sectionIndexTitleForSectionName:sectionName];
  }
}

- (void)modelHierarchyControllerDidChangeContent:(FBModelHierarchyController *)modelHierarchyController
{
  if (!CHECK_DATA_CONTROLLER(modelHierarchyController)) { return; }
  if ([_delegate respondsToSelector:@selector(controllerDidChangeContent:)]) {
    [_delegate controllerDidChangeContent:self];
  }
}

- (void)modelHierarchyControllerWillChangeContent:(FBModelHierarchyController *)modelHierarchyController
{
  if (!CHECK_DATA_CONTROLLER(modelHierarchyController)) { return; }
  if ([_delegate respondsToSelector:@selector(controllerWillChangeContent:)]) {
    [_delegate controllerWillChangeContent:self];
  }
}

@end
