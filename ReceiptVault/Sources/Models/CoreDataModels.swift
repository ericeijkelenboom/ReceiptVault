import Foundation
import CoreData

// MARK: - Receipt Entity
public class Receipt: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var shopName: String
    @NSManaged public var date: Date
    @NSManaged public var total: NSDecimalNumber?
    @NSManaged public var currency: String?
    @NSManaged public var rawText: String
    @NSManaged public var jpgPath: String?
    @NSManaged public var createdAt: Date
    @NSManaged public var quotaMonth: String // "2025-03" format for tracking monthly reset
    @NSManaged public var lineItems: NSSet? // Relationship to CDLineItem
}

// MARK: - LineItem Entity (Core Data Version)
public class CDLineItem: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var name: String
    @NSManaged public var quantity: NSDecimalNumber?
    @NSManaged public var unitPrice: NSDecimalNumber?
    @NSManaged public var totalPrice: NSDecimalNumber?
    @NSManaged public var receipt: Receipt? // Relationship back to Receipt
}

// MARK: - Extensions for Core Data Setup
extension Receipt {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<Receipt> {
        return NSFetchRequest<Receipt>(entityName: "Receipt")
    }

    static func sortedFetchRequest() -> NSFetchRequest<Receipt> {
        let request = fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Receipt.date, ascending: false)]
        return request
    }
}

extension CDLineItem {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDLineItem> {
        return NSFetchRequest<CDLineItem>(entityName: "CDLineItem")
    }
}

// MARK: - Core Data Model Builder
private func buildManagedObjectModel() -> NSManagedObjectModel {
    let model = NSManagedObjectModel()

    // Receipt Entity
    let receiptEntity = NSEntityDescription()
    receiptEntity.name = "Receipt"
    receiptEntity.managedObjectClassName = String(describing: Receipt.self)

    let idAttr = NSAttributeDescription()
    idAttr.name = "id"
    idAttr.attributeType = .UUIDAttributeType
    idAttr.isOptional = false
    idAttr.defaultValue = UUID()

    let shopNameAttr = NSAttributeDescription()
    shopNameAttr.name = "shopName"
    shopNameAttr.attributeType = .stringAttributeType
    shopNameAttr.isOptional = false
    shopNameAttr.defaultValue = ""

    let dateAttr = NSAttributeDescription()
    dateAttr.name = "date"
    dateAttr.attributeType = .dateAttributeType
    dateAttr.isOptional = false
    dateAttr.defaultValue = Date()

    let totalAttr = NSAttributeDescription()
    totalAttr.name = "total"
    totalAttr.attributeType = .decimalAttributeType
    totalAttr.isOptional = true

    let currencyAttr = NSAttributeDescription()
    currencyAttr.name = "currency"
    currencyAttr.attributeType = .stringAttributeType
    currencyAttr.isOptional = true

    let rawTextAttr = NSAttributeDescription()
    rawTextAttr.name = "rawText"
    rawTextAttr.attributeType = .stringAttributeType
    rawTextAttr.isOptional = false
    rawTextAttr.defaultValue = ""

    let jpgPathAttr = NSAttributeDescription()
    jpgPathAttr.name = "jpgPath"
    jpgPathAttr.attributeType = .stringAttributeType
    jpgPathAttr.isOptional = true

    let createdAtAttr = NSAttributeDescription()
    createdAtAttr.name = "createdAt"
    createdAtAttr.attributeType = .dateAttributeType
    createdAtAttr.isOptional = false
    createdAtAttr.defaultValue = Date()

    let quotaMonthAttr = NSAttributeDescription()
    quotaMonthAttr.name = "quotaMonth"
    quotaMonthAttr.attributeType = .stringAttributeType
    quotaMonthAttr.isOptional = false
    quotaMonthAttr.defaultValue = ""

    // LineItem Entity
    let lineItemEntity = NSEntityDescription()
    lineItemEntity.name = "CDLineItem"
    lineItemEntity.managedObjectClassName = String(describing: CDLineItem.self)

    let liIdAttr = NSAttributeDescription()
    liIdAttr.name = "id"
    liIdAttr.attributeType = .UUIDAttributeType
    liIdAttr.isOptional = false
    liIdAttr.defaultValue = UUID()

    let nameAttr = NSAttributeDescription()
    nameAttr.name = "name"
    nameAttr.attributeType = .stringAttributeType
    nameAttr.isOptional = false
    nameAttr.defaultValue = ""

    let quantityAttr = NSAttributeDescription()
    quantityAttr.name = "quantity"
    quantityAttr.attributeType = .decimalAttributeType
    quantityAttr.isOptional = true

    let unitPriceAttr = NSAttributeDescription()
    unitPriceAttr.name = "unitPrice"
    unitPriceAttr.attributeType = .decimalAttributeType
    unitPriceAttr.isOptional = true

    let totalPriceAttr = NSAttributeDescription()
    totalPriceAttr.name = "totalPrice"
    totalPriceAttr.attributeType = .decimalAttributeType
    totalPriceAttr.isOptional = true

    // Relationships
    let lineItemsRel = NSRelationshipDescription()
    lineItemsRel.name = "lineItems"
    lineItemsRel.destinationEntity = lineItemEntity
    lineItemsRel.isOptional = true
    lineItemsRel.deleteRule = .cascadeDeleteRule

    let receiptRel = NSRelationshipDescription()
    receiptRel.name = "receipt"
    receiptRel.destinationEntity = receiptEntity
    receiptRel.isOptional = true
    receiptRel.deleteRule = .nullifyDeleteRule

    // Set up inverse relationships
    lineItemsRel.inverseRelationship = receiptRel
    receiptRel.inverseRelationship = lineItemsRel

    // Set attributes and relationships
    receiptEntity.properties = [idAttr, shopNameAttr, dateAttr, totalAttr, currencyAttr, rawTextAttr, jpgPathAttr, createdAtAttr, quotaMonthAttr, lineItemsRel]
    lineItemEntity.properties = [liIdAttr, nameAttr, quantityAttr, unitPriceAttr, totalPriceAttr, receiptRel]

    model.entities = [receiptEntity, lineItemEntity]

    return model
}

// MARK: - Core Data Stack
class CoreDataStack {
    static let shared = CoreDataStack()

    lazy var persistentContainer: NSPersistentContainer = {
        let model = buildManagedObjectModel()
        let container = NSPersistentContainer(name: "ReceiptVault", managedObjectModel: model)

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        return container
    }()

    var viewContext: NSManagedObjectContext {
        return persistentContainer.viewContext
    }

    func saveContext() {
        let context = viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }

    // MARK: - CloudKit Migration (for Task 5)
    /// Call this method in Task 5 after CloudKit entitlements are properly configured
    func enableCloudKitSync() {
        // This will be implemented in Task 5 to migrate from NSPersistentContainer
        // to NSPersistentCloudKitContainer with proper CloudKit entitlements
        fatalError("CloudKit sync migration should be called in Task 5 after entitlements are configured")
    }
}
