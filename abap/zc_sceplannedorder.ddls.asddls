@EndUserText.label: 'SCE Planned Order'
@AccessControl.authorizationCheck: #CHECK
@UI.headerInfo: { typeName: 'Planned Order', typeNamePlural: 'Planned Orders', title: { value: 'Material' } }
@UI.presentationVariant: [{ qualifier: 'ByStart', sortOrder: [{ by: 'StartSeconds', direction: #ASC }],
                            visualizations: [{ type: #AS_LINEITEM }] }]
define view entity ZC_SCEPlannedOrder
  as projection on ZI_SCEPlannedOrder
{
      @UI.facet: [{ id: 'Details', type: #IDENTIFICATION_REFERENCE, label: 'Details', position: 10 }]
  key PlannedOrderUUID,
      DivisionUUID,
      GameUUID,
      @UI.lineItem: [{ position: 10 },
                     { type: #FOR_ACTION, dataAction: 'convertOrder', label: 'Convert' },
                     { type: #FOR_ACTION, dataAction: 'firmOrder', label: 'Firm' },
                     { type: #FOR_ACTION, dataAction: 'unfirmOrder', label: 'Unfirm' }]
      @UI.identification: [{ position: 10 }]
      @EndUserText.label: 'Material'
      Material,
      @EndUserText.label: 'Quantity'
      @UI.lineItem: [{ position: 20 }]
      @UI.identification: [{ position: 20 }]
      Quantity,
      @EndUserText.label: 'Start (s)'
      @UI.lineItem: [{ position: 30 }]
      @UI.identification: [{ position: 30 }]
      StartSeconds,
      @EndUserText.label: 'Finish (s)'
      @UI.lineItem: [{ position: 40 }]
      @UI.identification: [{ position: 40 }]
      FinishSeconds,
      @EndUserText.label: 'Planned for'
      @UI.lineItem: [{ position: 50 }]
      @UI.identification: [{ position: 50 }]
      PlannedFor,
      @EndUserText.label: 'Firmed'
      @UI.lineItem: [{ position: 55 }]
      @UI.identification: [{ position: 55 }]
      Firmed,
      @EndUserText.label: 'Exception'
      @UI.lineItem: [{ position: 60 }]
      @UI.identification: [{ position: 60 }]
      ExceptionText,
      _Division : redirected to parent ZC_SCEDivision,
      _Game     : redirected to ZC_SCEGame
}
