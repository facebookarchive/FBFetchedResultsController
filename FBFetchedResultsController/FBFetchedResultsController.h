/*
 *  Copyright (c) 2015, Facebook, Inc.
 *  All rights reserved.
 *
 *  This source code is licensed under the BSD-style license found in the
 *  LICENSE file in the root directory of this source tree. An additional grant 
 *  of patent rights can be found in the PATENTS file in the same directory.
 *
 */

#import <CoreData/CoreData.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBFetchedResultsControllerDelegate;

/**
 A drop-in replacement for NSFetchedResultsController built to work around the fact that NSFetchedResultsController does
 not work with parent/child contexts. See NSFetchedResultsController for documentation.
 
 IMPORTANT: Any time you call [NSManagedObjectContext -mergeChangesFromContextDidSaveNotification:], you must call
 [FBFetchedResultsController +didMergeChangesFromContextDidSaveNotification:intoContext:].
 */
@interface FBFetchedResultsController : NSObject

+ (void)didMergeChangesFromContextDidSaveNotification:(NSNotification *)notification
                                          intoContext:(NSManagedObjectContext *)context;

+ (void)deleteCacheWithName:(nullable NSString *)name;

- (instancetype)initWithFetchRequest:(NSFetchRequest *)fetchRequest
                managedObjectContext:(NSManagedObjectContext *)managedObjectContext
                  sectionNameKeyPath:(nullable NSString *)sectionNameKeyPath
                           cacheName:(nullable NSString *)cacheName;

@property (nullable, nonatomic, copy, readonly) NSString *cacheName; // not used
@property (nullable, nonatomic, assign) id <FBFetchedResultsControllerDelegate> delegate;
@property (nullable, nonatomic, copy, readonly) NSArray<__kindof NSManagedObject *> *fetchedObjects;
@property (nonatomic, retain, readonly) NSFetchRequest *fetchRequest;
@property (nonatomic, retain, readonly) NSManagedObjectContext *managedObjectContext;
@property (nonatomic, copy, readonly) NSArray<NSString *> *sectionIndexTitles;
@property (nonatomic, copy, readonly) NSString *sectionNameKeyPath;
@property (nonatomic, copy, readonly) NSArray<id<NSFetchedResultsSectionInfo>> *sections;

- (nullable NSIndexPath *)indexPathForObject:(__kindof NSManagedObject *)object;
- (__kindof NSManagedObject *)objectAtIndexPath:(NSIndexPath *)indexPath;
- (BOOL)performFetch:(NSError **)error;
- (NSInteger)sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)sectionIndex;
- (nullable NSString *)sectionIndexTitleForSectionName:(NSString *)sectionName;

@end

@protocol FBFetchedResultsControllerDelegate <NSObject>

@optional

- (void)controllerWillChangeContent:(FBFetchedResultsController *)controller;

- (void)controller:(FBFetchedResultsController *)controller
   didChangeObject:(__kindof NSManagedObject *)anObject
       atIndexPath:(nullable NSIndexPath *)indexPath
     forChangeType:(NSFetchedResultsChangeType)type
      newIndexPath:(nullable NSIndexPath *)newIndexPath;

- (void)controller:(FBFetchedResultsController *)controller
  didChangeSection:(id<NSFetchedResultsSectionInfo>)sectionInfo
           atIndex:(NSUInteger)sectionIndex
     forChangeType:(NSFetchedResultsChangeType)type;

- (void)controllerDidChangeContent:(FBFetchedResultsController *)controller;

- (NSString *)controller:(FBFetchedResultsController *)controller sectionIndexTitleForSectionName:(NSString *)sectionName;

@end

NS_ASSUME_NONNULL_END
