//
//  Garage.swift
//  GarageStorage
//
//  Created by Brian Arnold on 9/11/19.
//  Copyright © 2015-2024 Wellframe. All rights reserved.
//

import Foundation
import CoreData

/// The main Garage Storage interface for parking and retrieving objects.
///
/// The `Garage` is the main object that coordinates activity in Garage Storage. It's called a *Garage* because you can park pretty much anything in it, like, you know, a garage. The Garage handles the backing Core Data stack, as well as the saving and retrieving of data. You *park* objects in the Garage, and *retrieve* them later.
/// 
/// Any object going into or coming out of the Garage must conform to the `Codable` protocol. Some objects may need to also conform to either the `Hashable` protocol for nested objects, or the ``Mappable`` protocol (which is `Codable` and `Identifiable where ID == String`) for uniquely identified top-level objects.
///
/// For Objective-C compatibility, the ``MappableObject`` protocol may be used instead.
@objc(GSGarage)
public class Garage: NSObject {
    
    private static let modelName = "GarageStorage"
    
    private let persistentContainer: NSPersistentContainer

    /// An optional delegate for serializing/deserializing stored data. Specify this to add encryption to the stored data.
    @objc
    public weak var dataEncryptionDelegate: DataEncryptionDelegate?

    /// Autosave is set to true by default, for every operation that causes a change to the underlying Core Data Managed Object Context.
    ///
    /// When set to true, the garage will be saved after any operation that causes a change to the underlying Core Data Managed Object Context, including `park()`, `setSyncStatus()`, and `delete()`. When set to false, `save()` must be called instead, in order to persist those changes. You might want to set this to false to perform batch changes to many objects before saving them all, to optimize performance.
    @objc(autosaveEnabled)
    public var isAutosaveEnabled = true
    
    /// The domain for errors generated by GarageStorage.
    @objc
    public static let errorDomain = "GSErrorDomain"
    
    internal static func makeError(_ description: String) -> NSError {
        let userInfo = [NSLocalizedDescriptionKey : description]
        return NSError(domain: errorDomain, code: -1, userInfo: userInfo)
    }

    // MARK: - Initializing

    /// A convenience function that returns a `NSPersistentStoreDescription` of type `NSSQLLiteStoreType`, with a URL in the application Documents directory, of the specified store name.
    ///
    /// - parameter storeName: the name of the store, with an appropriate file extension (e.g., ".sqlite") appended.
    ///
    /// - returns: A `NSPersistentStoreDescription` of type `NSSQLiteStoreType`, with a URL in the application Documents directory, of the specified store name.
    public static func makePersistentStoreDescription(_ storeName: String) -> NSPersistentStoreDescription {
        let applicationDocumentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).last!
        let storeURL = applicationDocumentsDirectory.appendingPathComponent(storeName)
        let description = NSPersistentStoreDescription(url: storeURL)
        description.type = NSSQLiteStoreType
        return description
    }
    
    /// Creates a Garage with a default persistent store coordinator.
    /// This convenience initializer will also load the persistent store.
    /// - parameter garageName: The name of the garage without an extension, which will be used to create a store with the same name, appending ".sqlite".
    public convenience init(named garageName: String) {
        let storeName = "\(garageName).sqlite"
        let description = Garage.makePersistentStoreDescription(storeName)
        self.init(with: [description])
        
        loadPersistentStores { (description, error) in
            if let error = error {
                print("An error occurred loading persistent store \(description), error: \(error)")
            }
        }
    }
    
    /// Creates a Garage with the specified persistent store descriptions.
    /// This initializer will not immediately load the persistent stores.
    ///
    /// Once the Garage has been initialized, call ``loadPersistentStores(completionHandler:)`` to instruct the Garage to load the persistent stores and complete the creation of the Core Data stack.
    ///
    /// - parameter persistentStoreDescriptions: An array of `NSPersistentStoreDescription` to use in the Garage's Core Data stack.
    public init(with persistentStoreDescriptions: [NSPersistentStoreDescription]) {
        let garageModel = GarageModel().makeModel()
        self.persistentContainer = NSPersistentContainer(name: Garage.modelName, managedObjectModel: garageModel)
        let descriptions = persistentStoreDescriptions
        self.persistentContainer.persistentStoreDescriptions = descriptions
        super.init()
    }
 
    /// Loads the persistent stores.
    ///
    /// Once the Garage has been initialized, this function must be called to instruct the Garage to load the persistent stores and complete the creation of the Core Data stack.
    ///
    /// Once the completion handler has been called, the Garage is fully initialized and is ready for use. The completion handler will be called once for each persistent store that is created.
    ///
    /// If there is an error in the loading of the persistent stores, the `Error` will be returned to the completion block, with the associated `NSPersistentStoreDescription`.
    ///
    /// - parameter block: Once the loading of the persistent stores has completed, this block will be executed on the calling thread.
    @objc public func loadPersistentStores(completionHandler block: @escaping (NSPersistentStoreDescription, Error?) -> Void) {
        persistentContainer.loadPersistentStores(completionHandler: block)
    }
    
    // MARK: - Saving
    
    /// Saves all changes to the Garage to the persistent store. This will not affect in-memory objects.
    ///
    /// This only needs to be called if `isAutosaveEnabled` is set to `false`. No error is returned, but diagnostic text will be output to the console if an error occurs.
    @objc(saveGarage)
    public func save() {
        let context = persistentContainer.viewContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch let error as NSError {
            print("Error saving managed object context: \(error), \(error.userInfo)")
        }
    }
    
    internal func autosave() {
        if isAutosaveEnabled {
            save()
        }
    }

    internal func encrypt(_ data: Data) throws -> String {
        return try dataEncryptionDelegate?.encrypt(data) ?? String(data: data, encoding: .utf8)!
    }
    
    internal func decrypt(_ string: String) throws -> Data {
        return try dataEncryptionDelegate?.decrypt(string) ?? string.data(using: .utf8)!
    }

    // MARK: - Parking
    
    internal func makeCoreDataObject(_ type: String, identifier: String) -> CoreDataObject {
         let newObject = NSEntityDescription.insertNewObject(forEntityName: CoreDataObject.entityName, into: persistentContainer.viewContext) as! CoreDataObject
         
         newObject.gs_type = type
         newObject.gs_identifier = identifier
         newObject.gs_creationDate = Date()
         
         return newObject
     }

    internal func retrieveCoreDataObject(for type: String, identifier: String) -> CoreDataObject {
        return fetchObject(for: type, identifier: identifier) ?? makeCoreDataObject(type, identifier: identifier)
    }
    
    // MARK: - Retrieving
    
    internal func fetchObjects(for type: String, identifier: String?) -> [CoreDataObject] {
        let fetchRequest: NSFetchRequest<CoreDataObject> = CoreDataObject.fetchRequest()
        fetchRequest.predicate = CoreDataObject.predicate(for: type, identifier: identifier)
        let fetchedObjects = try? persistentContainer.viewContext.fetch(fetchRequest)
        
        return fetchedObjects ?? []
    }
    
    internal func fetchObject(for type: String, identifier: String?) -> CoreDataObject? {
        let fetchedObjects = fetchObjects(for: type, identifier: identifier)
        
        return fetchedObjects.count > 0 ? fetchedObjects[0] : nil
    }
    
    internal func fetchCoreDataObject(for type: String, identifier: String) throws -> CoreDataObject {
        guard let coreDataObject = fetchObject(for: type, identifier: identifier) else {
            throw Garage.makeError("failed to retrieve object of class: \(type) identifier: \(identifier)")
        }
        return coreDataObject
    }

    internal func fetchObjects(with syncStatus: SyncStatus, type: String?) throws -> [CoreDataObject] {
        let fetchRequest: NSFetchRequest<CoreDataObject> = CoreDataObject.fetchRequest()
        fetchRequest.predicate = CoreDataObject.predicate(for: syncStatus, type: type)
        
        return try persistentContainer.viewContext.fetch(fetchRequest)
    }
    
    // MARK: - Deleting
     
    internal func delete(_ object: CoreDataObject) throws {
        persistentContainer.viewContext.delete(object)
        
        autosave()
    }

    internal func deleteAll(_ objects: [CoreDataObject]) {
        guard objects.count > 0 else { return }
        
        for object in objects {
            persistentContainer.viewContext.delete(object)
        }
        
        autosave()
    }
    
    /// Deletes all objects from the Garage.
    @objc(deleteAllObjectsFromGarage)
    public func deleteAllObjects() {
        let fetchRequest: NSFetchRequest<CoreDataObject> = CoreDataObject.fetchRequest()
        guard let objects = try? persistentContainer.viewContext.fetch(fetchRequest) else { return }
        deleteAll(objects)
    }

}
