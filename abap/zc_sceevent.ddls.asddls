@EndUserText.label: 'SCE Goods Movement'
@AccessControl.authorizationCheck: #CHECK
@Metadata.allowExtensions: true
@UI.headerInfo: { typeName: 'Goods Movement', typeNamePlural: 'Goods Movements', title: { value: 'Material' }, description: { value: 'MovementType' } }
define view entity ZC_SCEEvent
  as projection on ZI_SCEEvent
{
      @UI.facet: [{ id: 'Details', type: #IDENTIFICATION_REFERENCE, label: 'Details', position: 10 }]
  key EventUUID,
      DivisionUUID,
      PlantUUID,
      OrderUUID,
      GameUUID,
      @EndUserText.label: 'Game second'
      @UI.lineItem: [{ position: 10 }]
      @UI.identification: [{ position: 10 }]
      GameSeconds,
      @EndUserText.label: 'Movement type'
      @UI.lineItem: [{ position: 20 }]
      @UI.identification: [{ position: 20 }]
      MovementType,
      @EndUserText.label: 'Material'
      @UI.lineItem: [{ position: 30 }]
      @UI.identification: [{ position: 30 }]
      Material,
      @EndUserText.label: 'Quantity'
      @UI.lineItem: [{ position: 40 }]
      @UI.identification: [{ position: 40 }]
      Quantity,
      @EndUserText.label: 'Minerals'
      @UI.lineItem: [{ position: 50 }]
      @UI.identification: [{ position: 50 }]
      MineralValue,
      @EndUserText.label: 'Gas'
      @UI.lineItem: [{ position: 60 }]
      @UI.identification: [{ position: 60 }]
      GasValue,
      @EndUserText.label: 'Source'
      @UI.lineItem: [{ position: 70 }]
      @UI.identification: [{ position: 70 }]
      EventSource,
      @EndUserText.label: 'Unit tag'
      @UI.identification: [{ position: 80 }]
      UnitTag,
      _Division  : redirected to parent ZC_SCEDivision,
      _Plant     : redirected to ZC_SCEPlant,
      _ProdOrder : redirected to ZC_SCEProdOrder,
      _Material  : redirected to ZC_SCEMaterial,
      _Game      : redirected to ZC_SCEGame
}
