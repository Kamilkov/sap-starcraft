@EndUserText.label: 'SCE Maintenance Order'
@AccessControl.authorizationCheck: #CHECK
@Metadata.allowExtensions: true
@UI.headerInfo: { typeName: 'Maintenance Order', typeNamePlural: 'Maintenance Orders', title: { value: 'Material' }, description: { value: 'OrderStatus' } }
@UI.presentationVariant: [{ qualifier: 'ByPriority',
                            sortOrder: [{ by: 'Priority', direction: #ASC }, { by: 'ReportedAt', direction: #ASC }],
                            visualizations: [{ type: #AS_LINEITEM }] }]
define view entity ZC_SCEMaintOrder
  as projection on ZI_SCEMaintOrder
{
      @UI.facet: [{ id: 'Details',   type: #IDENTIFICATION_REFERENCE, label: 'Details', position: 10 },
                  { id: 'Movements', type: #LINEITEM_REFERENCE, targetElement: '_Event', label: 'Goods Movements', position: 20 }]
  key OrderUUID,
      DivisionUUID,
      GameUUID,
      NotificationUUID,
      PlantUUID,
      @EndUserText.label: 'Material'
      @UI.lineItem: [{ position: 10 },
                     { type: #FOR_ACTION, dataAction: 'cancelOrder', label: 'Cancel Order' }]
      @UI.identification: [{ position: 10 },
                           { type: #FOR_ACTION, dataAction: 'cancelOrder', label: 'Cancel Order' }]
      Material,
      @EndUserText.label: 'Equipment'
      @UI.lineItem: [{ position: 20 }]
      @UI.identification: [{ position: 20 }]
      UnitTag,
      @EndUserText.label: 'Status'
      @UI.lineItem: [{ position: 30 }]
      @UI.identification: [{ position: 30 }]
      OrderStatus,
      @EndUserText.label: 'Bot message'
      @UI.lineItem: [{ position: 35 }]
      @UI.identification: [{ position: 35 }]
      StatusText,
      @EndUserText.label: 'Priority'
      @UI.lineItem: [{ position: 40 }]
      @UI.identification: [{ position: 40 }]
      Priority,
      @EndUserText.label: 'Reported at (s)'
      @UI.identification: [{ position: 45 }]
      ReportedAt,
      @EndUserText.label: 'Released at (s)'
      @UI.lineItem: [{ position: 50 }]
      @UI.identification: [{ position: 50 }]
      ReleasedAt,
      @EndUserText.label: 'Started at (s)'
      @UI.lineItem: [{ position: 60 }]
      @UI.identification: [{ position: 60 }]
      StartedAt,
      @EndUserText.label: 'Confirmed at (s)'
      @UI.lineItem: [{ position: 70 }]
      @UI.identification: [{ position: 70 }]
      ConfirmedAt,
      @EndUserText.label: 'SCV'
      @UI.lineItem: [{ position: 80 }]
      @UI.identification: [{ position: 80 }]
      WorkerTag,
      // repair cost: the 261 posted with this order (there is no 262: the game refunds no repair)
      @EndUserText.label: 'Cost minerals'
      @UI.lineItem: [{ position: 90 }]
      @UI.identification: [{ position: 90 }]
      _Consumption.ConsumedMinerals as ActualMinerals,
      @EndUserText.label: 'Cost gas'
      @UI.lineItem: [{ position: 100 }]
      @UI.identification: [{ position: 100 }]
      _Consumption.ConsumedGas      as ActualGas,
      _Division : redirected to parent ZC_SCEDivision,
      _Game     : redirected to ZC_SCEGame,
      _Plant    : redirected to ZC_SCEPlant,
      _Material : redirected to ZC_SCEMaterial,
      _Event    : redirected to ZC_SCEEvent,
      _Notification : redirected to ZC_SCENotification
}
