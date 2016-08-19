part of aqueduct;

/// Instances are a representation of a table in a database.
///
/// A model entity describes all of the properties of a [Model] object. A property is either an attribute or
/// a relationship. Attributes always map to a similarly named column in the persistent storage for a [Model].
/// A relationship property represents a foreign key value in persistent storage in the case of a [belongsTo] relationship.
/// For [hasOne] and [hasMany] relationships, the relationship property is not backed in persistent storage, but is still
/// a property of the [Model] object.
class ModelEntity {
  /// Creates an instance of a ModelEntity.
  ///
  /// You should never call this method directly, it will be called by [DataModel].
  ModelEntity(this.dataModel, this.instanceTypeMirror, this.persistentInstanceTypeMirror);

  /// The type of instances represented by this entity.
  ///
  /// Model objects are made up of two components, a persistent type and an instance type. Applications
  /// use instance types. This value is the [ClassMirror] on that type.
  final ClassMirror instanceTypeMirror;

  /// The type of persistent instances represented by this entity.
  ///
  /// Model objects are made up of two components, a persistent type and an instance type. This value
  /// is the [ClassMirror] on the persistent portion of a [Model] object.
  final ClassMirror persistentInstanceTypeMirror;

  /// The [DataModel] this instance belongs to.
  final DataModel dataModel;

  /// Schema of the model as returned from a request
  APISchemaObject get documentedResponseSchema {
    if (_documentedResponseSchema == null) {
      _documentedResponseSchema = new APISchemaObject()
        ..title = MirrorSystem.getName(instanceTypeMirror.simpleName)
        ..type = APISchemaObjectTypeObject
        ..properties = _propertiesForEntity(this);
    }
    return _documentedResponseSchema;
  }

  Map<String, APISchemaObject> _propertiesForEntity(ModelEntity me) {
    Map<String, APISchemaObject> schemaProperties = {};
    me.attributes.forEach((key, attribute) {
      schemaProperties[attribute.name] = new APISchemaObject()
        ..title = attribute.name
        ..type = _schemaObjectTypeForPropertyType(attribute.type)
        ..format = _schemaObjectFormatForPropertyType(attribute.type);
    });

    me.relationships.values
        .where((relationship) => relationship.relationshipType != RelationshipType.belongsTo)
        .forEach((relationship) {
      schemaProperties[relationship.name] = new APISchemaObject()
        ..title = relationship.name
        ..type = relationship.relationshipType == RelationshipType.hasOne
            ? APISchemaObjectTypeObject
            : APISchemaObjectTypeArray
        ..properties = _propertiesForEntity(relationship.destinationEntity);
    });

    return schemaProperties;
  }
  APISchemaObject _documentedResponseSchema;

  String _schemaObjectTypeForPropertyType(PropertyType pt) {
    switch (pt) {
      case PropertyType.integer:
      case PropertyType.bigInteger:
        return APISchemaObjectTypeInteger;
      case PropertyType.string:
      case PropertyType.datetime:
        return APISchemaObjectTypeString;
      case PropertyType.boolean:
        return APISchemaObjectTypeBoolean;
      case PropertyType.doublePrecision:
        return APISchemaObjectTypeNumber;
      default:
        return null;
    }
  }

  String _schemaObjectFormatForPropertyType(PropertyType pt) {
    switch (pt) {
      case PropertyType.integer:
        return APISchemaObjectFormatInt32;
      case PropertyType.bigInteger:
        return APISchemaObjectFormatInt64;
      case PropertyType.datetime:
        return APISchemaObjectFormatDateTime;
      case PropertyType.doublePrecision:
        return APISchemaObjectFormatDouble;
      default:
        return null;
    }
  }

  /// All attribute values of this entity.
  ///
  /// An attribute maps to a single column or field in a database that is a single value, such as a string, integer, etc.
  /// The keys are the case-sensitive name of the attribute. Values that represent a relationship to another object
  /// are not stored in [attributes].
  Map<String, AttributeDescription> attributes;

  /// All relationship values of this entity.
  ///
  /// A relationship represents a value that is another [Model] or [List] of [Model]s. Not all relationships
  /// correspond to a column or field in a database. In a relational database, if the [RelationshipDescription]
  /// has a [relationshipType] of [RelationshipType.belongsTo], the relationship represents the foreign key column.
  /// Keys are the case-sensitive name of the relationship.
  Map<String, RelationshipDescription> relationships;

  /// All properties (relationships and attributes) of this entity.
  ///
  /// The string key is the name of the property, case-sensitive. Values will be instances of either [AttributeDescription]
  /// or [RelationshipDescription]. This is the concatenation of [attributes] and [relationships].
  Map<String, PropertyDescription> get properties {
    var all = new Map.from(attributes);
    if (relationships != null) {
      all.addAll(relationships);
    }
    return all;
  }

  /// The list of default properties returned when querying an instance of this type.
  ///
  /// By default, a [Query] will return all the properties named in this list. You may specify
  /// a different set of properties by setting the [Query]'s [resultProperties] value. The default
  /// set of properties is a list of all attributes that do not have the [omitByDefault] flag
  /// set in their [Attributes] and all [RelationshipType.belongsTo] relationships.
  List<String> get defaultProperties {
    if (_defaultProperties == null) {
      _defaultProperties = attributes.values
          .where((prop) => prop.isIncludedInDefaultResultSet)
          .map((prop) => prop.name)
          .toList();
      _defaultProperties.addAll(relationships.values
          .where((prop) => prop.isIncludedInDefaultResultSet && prop.relationshipType == RelationshipType.belongsTo)
          .map((prop) => prop.name)
          .toList());
    }
    return _defaultProperties;
  }
  List<String> _defaultProperties;

  /// Name of primaryKey property.
  ///
  /// If this has a primary key (as determined by the having an [Attributes] with [Attributes.primaryKey] set to true,
  /// returns the name of that property. Otherwise, returns null.
  String get primaryKey {
    return _primaryKey;
  }
  String _primaryKey;

  /// Name of table in database.
  ///
  /// By default, the table will be named by the persistent type, e.g., a model class defined as class User extends Model<_User> implements _User has a persistent
  /// type of _User. The table will be named _User. You may implement the static method [tableName] on the persistent type to return a [String] table
  /// name override this behavior. If this method is implemented, this property will be the returned [String].
  String get tableName {
    return _tableName;
  }
  String _tableName;

  /// Derived from this' [tableName].
  int get hashCode {
    return tableName.hashCode;
  }

  /// Creates an instance of this entity from a list of [MappingElement]s.
  ///
  /// This method is used by a [ModelContext] to instantiate entities from a row
  /// returned from a database. It will initialize all column values, including belongsTo
  /// relationships. It will not populate data from hasMany or hasOne relationships
  /// that were populated in a join query, as this is the responsibility of the context.
  Model instanceFromMappingElements(List<MappingElement> elements) {
    Model instance = instanceTypeMirror.newInstance(new Symbol(""), []).reflectee;

    elements.forEach((e) {
      if (e is! JoinMappingElement) {
        if (e.property is RelationshipDescription) {
          // A belongsTo relationship, keep the foreign key.
          if (e.value != null) {
            RelationshipDescription relDesc = e.property;
            Model innerInstance = relDesc.destinationEntity.instanceTypeMirror.newInstance(new Symbol(""), []).reflectee;
            innerInstance.dynamicBacking[relDesc.destinationEntity.primaryKey] = e.value;
            instance.dynamicBacking[e.property.name] = innerInstance;
          }
        } else {
          instance.dynamicBacking[e.property.name] = e.value;
        }
      }
    });

    return instance;
  }


  /// Two entities are considered equal if they have the same [tableName].
  operator ==(ModelEntity other) {
    return tableName == other.tableName;
  }

  String toString() {
    return "ModelEntity on $tableName";
  }
}