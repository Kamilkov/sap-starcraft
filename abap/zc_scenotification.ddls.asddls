@EndUserText.label: 'SCE Maintenance Notification'
@AccessControl.authorizationCheck: #CHECK
@Metadata.allowExtensions: true
@UI.headerInfo: { typeName: 'Maintenance Notification', typeNamePlural: 'Maintenance Notifications', title: { value: 'Material' }, description: { value: 'NotificationStatus' } }
@UI.presentationVariant: [{ qualifier: 'ByPriority',
                            sortOrder: [{ by: 'Priority', direction: #ASC }, { by: 'ReportedAt', direction: #ASC }],
                            visualizations: [{ type: #AS_LINEITEM }] }]
define view entity ZC_SCENotification
  as projection on ZI_SCENotification
{
      @UI.facet: [{ id: 'Details', type: #IDENTIFICATION_REFERENCE, label: 'Details', position: 10 },
                  { id: 'Orders',  type: #PRESENTATIONVARIANT_REFERENCE, targetElement: '_MaintOrder', targetQualifier: 'ByPriority', label: 'Maintenance Orders', position: 20 }]
  key NotificationUUID,
      DivisionUUID,
      GameUUID,
      PlantUUID,
      @EndUserText.label: 'Material'
      @UI.lineItem: [{ position: 10 },
                     { type: #FOR_ACTION, dataAction: 'createOrder', label: 'Create Repair Order' }]
      @UI.identification: [{ position: 10 },
                           { type: #FOR_ACTION, dataAction: 'createOrder', label: 'Create Repair Order' }]
      Material,
      @EndUserText.label: 'Equipment'
      @UI.lineItem: [{ position: 20 }]
      @UI.identification: [{ position: 20 }]
      UnitTag,
      @EndUserText.label: 'Status'
      @UI.lineItem: [{ position: 30 }]
      @UI.identification: [{ position: 30 }]
      NotificationStatus,
      @EndUserText.label: 'Bot message'
      @UI.lineItem: [{ position: 35 }]
      @UI.identification: [{ position: 35 }]
      StatusText,
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
      @EndUserText.label: 'Reported at (s)'
      @UI.lineItem: [{ position: 70 }]
      @UI.identification: [{ position: 70 }]
      ReportedAt,
      @EndUserText.label: 'Closed at (s)'
      @UI.lineItem: [{ position: 80 }]
      @UI.identification: [{ position: 80 }]
      ClosedAt,
      _Division   : redirected to parent ZC_SCEDivision,
      _Game       : redirected to ZC_SCEGame,
      _Plant      : redirected to ZC_SCEPlant,
      _Material   : redirected to ZC_SCEMaterial,
      _MaintOrder : redirected to ZC_SCEMaintOrder
}
