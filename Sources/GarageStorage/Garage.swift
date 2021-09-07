//
//  Garage.swift
//  GarageStorage
//
//  Created by Brian Arnold on 9/11/19.
//  Copyright © 2015-2020 Wellframe. All rights reserved.
//

import Foundation
import CoreData

/// If your application requires data encryption, this protocol provides the relevant hooks.
@objc(GSDataEncryptionDelegate)
public protocol DataEncryptionDelegate: NSObjectProtocol {
    
    /// This is called when the Core Data object's underlying data is about to be stored. Provide an implementation that encrypts to a string.
    @objc func encrypt(_ data: Data) throws -> String
    
    /// This is called when the Core Data object's data is about to be accessed. Provide an implementation that decrypts the string.
    @objc func decrypt(_ string: String) throws -> Data
    
}

/// The main Garage Storage interface for parking and retrieving objects.
@objc(GSGarage)
public class Garage: NSObject {
    
    private static let modelName = "GarageStorage"
    
    private let persistentContainer: PersistentContainer

    /// An optional delegate for serializing/deserializing stored data.
    @objc
    public weak var dataEncryptionDelegate: DataEncryptionDelegate?

    /// Since GarageStorage is backed by Core Data, changes to the managed object context are not automatically saved to disk. Therefore, after each parkObject/setSyncStatus/deleteObject, `save()` must be called in order to persist those changes. However, when `isAutosaveEnabled` is set to true, the garage will be saved after any operation that causes a change to the MOC. When false, save calls must be performed manually. This is set to true by default.
    @objc(autosaveEnabled)
    public var isAutosaveEnabled = true
    
    /// For errors generated by GarageStorage
    @objc
    public static let errorDomain = "GSErrorDomain"
    
    internal static func makeError(_ description: String) -> NSError {
        let userInfo = [NSLocalizedDescriptionKey : description]
        return NSError(domain: errorDomain, code: -1, userInfo: userInfo)
    }

    // MARK: - Initializing
    
    private static var defaultStoreName = "GarageStorage.sqlite"
    
    private static var defaultDescription: PersistentStoreDescription = {
        return makePersistentStoreDescription(defaultStoreName)
    }()

    /// A convenience function that returns a PersistentStoreDescription of type NSSQLLiteStoreType, with a URL in the application Documents directory, of the specified store name.
    ///
    /// - parameter storeName: the name of the store.
    ///
    /// - returns: A PersistentStoreDescription of type NSSQLiteStoreType, with a URL in the application Documents directory, of the specified store name.
    public static func makePersistentStoreDescription(_ storeName: String) -> PersistentStoreDescription {
        let applicationDocumentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).last!
        let storeURL = applicationDocumentsDirectory.appendingPathComponent(storeName)
        let description = PersistentStoreDescription(url: storeURL)
        description.type = NSSQLiteStoreType
        return description
    }
    
    /// Creates a Garage with a default peristent store coordinator and object mapper.
    /// This convenience initalizer will also load the persistent store.
    public convenience override init() {
        self.init(with: nil)
        
        loadPersistentStores { (description, error) in
            if let error = error {
                print("An error occurred loading persistent store \(description), error: \(error)")
            }
        }
    }
    
    /// Creates a Garage with the specified persistent store descriptions and object mapper.
    ///
    /// - note: Once the Garage has been initialized, you need to execute `loadPersistentStores(completionHandler:)` to instruct the Garage to load the persistent stores and complete the creation of the Core Data stack.
    ///
    /// - parameter persistentStoreDescriptions: An array of PersistentStoreDescription to use in the Garage's Core Data Stack. If nil is passed in, a default description will be used.
    public init(with persistentStoreDescriptions: [PersistentStoreDescription]? = nil) {
        let garageModel = GarageModel().makeModel()
        self.persistentContainer = PersistentContainer(name: Garage.modelName, managedObjectModel: garageModel)
        let descriptions = persistentStoreDescriptions ?? [Garage.defaultDescription]
        self.persistentContainer.persistentStoreDescriptions = descriptions
        super.init()
    }
 
    /// Loads the persistent stores.
    ///
    /// Once the Garage has been initialized, you need to execute `loadPersistentStores(completionHandler:)` to instruct the Garage to load the persistent stores and complete the creation of the Core Data stack.
    ///
    /// Once the completion handler has fired, the Garage is fully initialized and is ready for use. The completion handler will be called once for each persistent store that is created.
    ///
    /// If there is an error in the loading of the persistent stores, the `NSError` value will be populated.
    ///
    /// - parameter block: Once the loading of the persistent stores has completed, this block will be executed on the calling thread.
    @objc public func loadPersistentStores(completionHandler block: (PersistentStoreDescription, Error?) -> Void) {
        persistentContainer.loadPersistentStores(completionHandler: block)
    }
    
    // MARK: - Saving
    
    /// Saves all changes to the Garage to the persistent store. This will not affect in-memory objects.
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
