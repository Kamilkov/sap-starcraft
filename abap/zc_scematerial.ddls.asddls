@EndUserText.label: 'SCE Material'
@AccessControl.authorizationCheck: #CHECK
@Metadata.allowExtensions: true
@Search.searchable: true
@UI.headerInfo: { typeName: 'Material', typeNamePlural: 'Materials', title: { value: 'Material' } }
define root view entity ZC_SCEMaterial
  provider contract transactional_query
  as projection on ZI_SCEMaterial
{
  key MaterialUUID,
      @UI.lineItem: [{ position: 10 }]
      @UI.selectionField: [{ position: 10 }]
      @Search.defaultSearchElement: true
      Material,
      @UI.lineItem: [{ position: 20 }]
      @UI.selectionField: [{ position: 20 }]
      CompanyCode,
      @UI.lineItem: [{ position: 30 }]
      @UI.selectionField: [{ position: 30 }]
      Category,
      @UI.lineItem: [{ position: 40 }]
      MineralCost,
      @UI.lineItem: [{ position: 50 }]
      GasCost,
      @UI.lineItem: [{ position: 60 }]
      SupplyCost,
      @EndUserText.label: 'Supply provided'
      @UI.lineItem: [{ position: 65 }]
      SupplyProvided,
      @UI.lineItem: [{ position: 70 }]
      BuildSeconds,
      @UI.lineItem: [{ position: 80 }]
      ProducedBy,
      @UI.lineItem: [{ position: 90 }]
      Prerequisite,
      LastChangedAt
}
