@EndUserText.label: 'SCE Plant'
@AccessControl.authorizationCheck: #CHECK
@Metadata.allowExtensions: true
@UI.headerInfo: { typeName: 'Plant', typeNamePlural: 'Plants', title: { value: 'PlantCode' } }
define view entity ZC_SCEPlant
  as projection on ZI_SCEPlant
{
      @UI.facet: [{ id: 'Details', type: #IDENTIFICATION_REFERENCE, label: 'Details', position: 10 }]
  key PlantUUID,
      DivisionUUID,
      GameUUID,
      @EndUserText.label: 'Outpost'
      @UI.lineItem: [{ position: 10 }]
      @UI.identification: [{ position: 10 }]
      PlantCode,
      @EndUserText.label: 'Position X'
      @UI.lineItem: [{ position: 20 }]
      @UI.identification: [{ position: 20 }]
      PosX,
      @EndUserText.label: 'Position Y'
      @UI.lineItem: [{ position: 30 }]
      @UI.identification: [{ position: 30 }]
      PosY,
      @EndUserText.label: 'Founded at (s)'
      @UI.lineItem: [{ position: 40 }]
      @UI.identification: [{ position: 40 }]
      FoundedAt,
      @EndUserText.label: 'Closed at (s)'
      @UI.lineItem: [{ position: 50 }]
      @UI.identification: [{ position: 50 }]
      ClosedAt,
      _Division : redirected to parent ZC_SCEDivision,
      _Game     : redirected to ZC_SCEGame
}
