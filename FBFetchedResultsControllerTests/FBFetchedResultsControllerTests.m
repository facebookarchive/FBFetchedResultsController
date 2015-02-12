// Copyright 2004-present Facebook. All Rights Reserved.

#import <CoreData/CoreData.h>
#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>

#import "FBFetchedResultsController.h"

@interface FBFetchedResultsControllerTests : XCTestCase <FBFetchedResultsControllerDelegate, NSFetchedResultsControllerDelegate>
{
  NSPersistentStoreCoordinator *_persistentStoreCoordinator;
  NSManagedObjectContext *_managedObjectContext;
}
@end

@implementation FBFetchedResultsControllerTests

#pragma mark - Setup

- (void)setUp
{
  [super setUp];

  _persistentStoreCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:
                                 [[NSManagedObjectModel alloc] initWithContentsOfURL:
                                  [[[NSBundle bundleForClass:[self class]] resourceURL]
                                   URLByAppendingPathComponent:@"Model.momd"]]];

  _managedObjectContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
  _managedObjectContext.persistentStoreCoordinator = _persistentStoreCoordinator;
}


- (void)tearDown
{
  _managedObjectContext = nil;
  _persistentStoreCoordinator = nil;
  [super tearDown];
}

- (void)testSimpleFetchEquivalence
{
  NSEntityDescription *carEntity = [[_persistentStoreCoordinator managedObjectModel] entitiesByName][@"Car"];

  NSManagedObject *redCar = [[NSManagedObject alloc] initWithEntity:carEntity insertIntoManagedObjectContext:_managedObjectContext];
  [redCar setValue:@"red" forKey:@"color"];
  NSManagedObject *blueCar = [[NSManagedObject alloc] initWithEntity:carEntity insertIntoManagedObjectContext:_managedObjectContext];
  [blueCar setValue:@"blue" forKey:@"color"];

  NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"Car"];
  fetchRequest.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"color" ascending:YES]];

  FBFetchedResultsController *fbFRC =
  [[FBFetchedResultsController alloc] initWithFetchRequest:fetchRequest
                                      managedObjectContext:_managedObjectContext
                                        sectionNameKeyPath:nil
                                                 cacheName:nil];
  [fbFRC performFetch:NULL];

  NSFetchedResultsController *nsFRC =
  [[NSFetchedResultsController alloc] initWithFetchRequest:fetchRequest
                                      managedObjectContext:_managedObjectContext
                                        sectionNameKeyPath:nil
                                                 cacheName:nil];
  [nsFRC performFetch:NULL];

  XCTAssertEqualObjects([fbFRC fetchedObjects], [nsFRC fetchedObjects]);
}

- (void)testPredicateAppliedToFetch
{
  NSEntityDescription *carEntity = [[_persistentStoreCoordinator managedObjectModel] entitiesByName][@"Car"];

  NSManagedObject *redCar = [[NSManagedObject alloc] initWithEntity:carEntity insertIntoManagedObjectContext:_managedObjectContext];
  [redCar setValue:@"red" forKey:@"color"];
  NSManagedObject *blueCar = [[NSManagedObject alloc] initWithEntity:carEntity insertIntoManagedObjectContext:_managedObjectContext];
  [blueCar setValue:@"blue" forKey:@"color"];

  NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:@"Car"];
  fetchRequest.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"color" ascending:YES]];
  fetchRequest.predicate = [NSPredicate predicateWithFormat:@"color='red'"];

  FBFetchedResultsController *fbFRC =
  [[FBFetchedResultsController alloc] initWithFetchRequest:fetchRequest
                                      managedObjectContext:_managedObjectContext
                                        sectionNameKeyPath:nil
                                                 cacheName:nil];
  [fbFRC performFetch:NULL];

  XCTAssertEqualObjects([fbFRC fetchedObjects], @[redCar]);
}

@end
