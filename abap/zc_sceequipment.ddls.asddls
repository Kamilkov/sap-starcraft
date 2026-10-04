@EndUserText.label: 'SCE Equipment'
@AccessControl.authorizationCheck: #CHECK
@UI.headerInfo: { typeName: 'Equipment', typeNamePlural: 'Equipment', title: { value: 'Material' }, description: { value: 'EquipmentStatus' } }
@UI.presentationVariant: [{ qualifier: 'ByReceipt',
                            sortOrder: [{ by: 'ReceivedAt', direction: #ASC }, { by: 'UnitTag', direction: #ASC }],
                            visualizations: [{ type: #AS_LINEITEM }] }]
define view entity ZC_SCEEquipment
  as select from ZI_SCEEquipment
  association [0..*] to ZC_SCENotification as _Notification on  $projection.DivisionUUID = _Notification.DivisionUUID
                                                            and $projection.UnitTag      = _Notification.UnitTag
  association [0..*] to ZC_SCEMaintOrder   as _MaintOrder   on  $projection.DivisionUUID = _MaintOrder.DivisionUUID
                                                            and $projection.UnitTag      = _MaintOrder.UnitTag
  association [0..*] to ZC_SCEEvent        as _Movement     on  $projection.DivisionUUID = _Movement.DivisionUUID
                                                            and $projection.UnitTag      = _Movement.UnitTag
{
      @UI.facet: [{ id: 'Details',       type: #IDENTIFICATION_REFERENCE, label: 'Details', position: 10 },
                  { id: 'Notifications', type: #PRESENTATIONVARIANT_REFERENCE, targetElement: '_Notification', targetQualifier: 'ByPriority', label: 'Maintenance Notifications', position: 20 },
                  { id: 'Orders',        type: #PRESENTATIONVARIANT_REFERENCE, targetElement: '_MaintOrder',   targetQualifier: 'ByPriority', label: 'Maintenance Orders',        position: 30 },
                  { id: 'History',       type: #LINEITEM_REFERENCE,            targetElement: '_Movement',                                    label: 'History',                   position: 40 }]
  key DivisionUUID,
      @EndUserText.label: 'Equipment'
      @UI.lineItem: [{ position: 10 }]
      @UI.identification: [{ position: 10 }]
  key UnitTag,
      _Division.GameUUID as GameUUID,
      @EndUserText.label: 'Material'
      @UI.lineItem: [{ position: 20 }]
      @UI.identification: [{ position: 20 }]
      Material,
      @EndUserText.label: 'Status'
      @UI.lineItem: [{ position: 30 }]
      @UI.identification: [{ position: 30 }]
      EquipmentStatus,
      @EndUserText.label: 'Priority'
      @UI.lineItem: [{ position: 40 }]
      @UI.identification: [{ position: 40 }]
      Priority,
      @EndUserText.label: 'Health'
      @UI.lineItem: [{ position: 50 }]
      @UI.identification: [{ position: 50 }]
      Health,
      @EndUserText.label: 'Health max'
      @UI.lineItem: [{ position: 60 }]
      @UI.identification: [{ position: 60 }]
      HealthMax,
      // the functional location: the outpost the structure was received at
      @EndUserText.label: 'Outpost'
      @UI.lineItem: [{ position: 70 }]
      @UI.identification: [{ position: 70 }]
      _Plant.PlantCode   as PlantCode,
      PlantUUID,
      OrderUUID,
      @EndUserText.label: 'Received at (s)'
      @UI.lineItem: [{ position: 80 }]
      @UI.identification: [{ position: 80 }]
      ReceivedAt,
      @EndUserText.label: 'Scrapped at (s)'
      @UI.lineItem: [{ position: 90 }]
      @UI.identification: [{ position: 90 }]
      ScrappedAt,
      @EndUserText.label: 'Source'
      @UI.identification: [{ position: 100 }]
      EventSource,
      _Notification,
      _MaintOrder,
      _Movement
}
