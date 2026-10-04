@EndUserText.label: 'SCE Serial Number'
@AccessControl.authorizationCheck: #CHECK
@UI.headerInfo: { typeName: 'Serial Number', typeNamePlural: 'Serial Numbers', title: { value: 'Material' }, description: { value: 'SerialStatus' } }
@UI.presentationVariant: [{ qualifier: 'ByReceipt',
                            sortOrder: [{ by: 'ReceivedAt', direction: #ASC }, { by: 'UnitTag', direction: #ASC }],
                            visualizations: [{ type: #AS_LINEITEM }] }]
define view entity ZC_SCESerialNumber
  as select from ZI_SCESerialNumber
  association [0..*] to ZC_SCEEvent as _Movement on  $projection.DivisionUUID = _Movement.DivisionUUID
                                                 and $projection.UnitTag      = _Movement.UnitTag
{
      @UI.facet: [{ id: 'Details', type: #IDENTIFICATION_REFERENCE, label: 'Details', position: 10 },
                  { id: 'History', type: #LINEITEM_REFERENCE, targetElement: '_Movement', label: 'History', position: 20 }]
  key DivisionUUID,
      @EndUserText.label: 'Serial number'
      @UI.lineItem: [{ position: 10 }]
      @UI.identification: [{ position: 10 }]
  key UnitTag,
      _Division.GameUUID as GameUUID,
      @EndUserText.label: 'Material'
      @UI.lineItem: [{ position: 20 }]
      @UI.identification: [{ position: 20 }]
      Material,
      @EndUserText.label: 'Category'
      @UI.lineItem: [{ position: 30 }]
      @UI.identification: [{ position: 30 }]
      Category,
      @EndUserText.label: 'Status'
      @UI.lineItem: [{ position: 40 }]
      @UI.identification: [{ position: 40 }]
      SerialStatus,
      @EndUserText.label: 'Outpost'
      @UI.lineItem: [{ position: 50 }]
      @UI.identification: [{ position: 50 }]
      _Plant.PlantCode   as PlantCode,
      PlantUUID,
      OrderUUID,
      @EndUserText.label: 'Received at (s)'
      @UI.lineItem: [{ position: 60 }]
      @UI.identification: [{ position: 60 }]
      ReceivedAt,
      @EndUserText.label: 'Scrapped at (s)'
      @UI.lineItem: [{ position: 70 }]
      @UI.identification: [{ position: 70 }]
      ScrappedAt,
      @EndUserText.label: 'Source'
      @UI.lineItem: [{ position: 80 }]
      @UI.identification: [{ position: 80 }]
      EventSource,
      _Movement
}
