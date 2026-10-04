@EndUserText.label: 'SCE Planned Requirement'
@AccessControl.authorizationCheck: #CHECK
@UI.headerInfo: { typeName: 'Planned Requirement', typeNamePlural: 'Planned Requirements', title: { value: 'Material' } }
@UI.presentationVariant: [{ qualifier: 'ByDue', sortOrder: [{ by: 'DueSeconds', direction: #ASC }],
                            visualizations: [{ type: #AS_LINEITEM }] }]
define view entity ZC_SCEPIR
  as projection on ZI_SCEPIR
{
      @UI.facet: [{ id: 'Details', type: #IDENTIFICATION_REFERENCE, label: 'Details', position: 10 }]
  key RequirementUUID,
      DivisionUUID,
      GameUUID,
      @EndUserText.label: 'Material'
      @UI.lineItem: [{ position: 10 },
                     { type: #FOR_ACTION, dataAction: 'deleteRequirement', label: 'Delete' }]
      @UI.identification: [{ position: 10 }]
      Material,
      @EndUserText.label: 'Quantity'
      @UI.lineItem: [{ position: 20 }]
      @UI.identification: [{ position: 20 }]
      Quantity,
      @EndUserText.label: 'Due (s)'
      @UI.lineItem: [{ position: 30 }]
      @UI.identification: [{ position: 30 }]
      DueSeconds,
      _Division : redirected to parent ZC_SCEDivision,
      _Game     : redirected to ZC_SCEGame
}
