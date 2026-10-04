@EndUserText.label: 'Economy Analysis'
@AccessControl.authorizationCheck: #CHECK
@OData.applySupportedForAggregation: #FULL
@UI.headerInfo: { typeName: 'Goods Movement', typeNamePlural: 'Goods Movements' }
@UI.chart: [{ qualifier: 'EconomyPerMinute', title: 'Economy per minute', chartType: #COLUMN_STACKED,
              dimensions: [ 'GameMinute', 'MovementType' ], measures: [ 'ValueMin' ],
              dimensionAttributes: [{ dimension: 'GameMinute', role: #CATEGORY }, { dimension: 'MovementType', role: #SERIES }],
              measureAttributes: [{ measure: 'ValueMin', role: #AXIS_1 }] }]
@UI.presentationVariant: [{ sortOrder: [{ by: 'GameSeconds', direction: #ASC }],
                            visualizations: [{ type: #AS_CHART, qualifier: 'EconomyPerMinute' }, { type: #AS_LINEITEM }] }]
define view entity ZC_SCEMovementAnalysis
  as select from ZI_SCEMovementAnalysis as M
    inner join   ZI_SCEMovementValueMin as V on V.EventUUID = M.EventUUID
{
      @UI.hidden: true
  key M.EventUUID,
      @EndUserText.label: 'Game'
      @ObjectModel.text.element: [ 'GameName' ]
      @UI.textArrangement: #TEXT_ONLY
      @Consumption.valueHelpDefinition: [{ entity: { name: 'ZC_SCEGameVH', element: 'GameUUID' } }]
      @UI.selectionField: [{ position: 20 }]
      @UI.lineItem: [{ position: 10 }]
      M.GameUUID,
      @EndUserText.label: 'Map'
      M.MapName,
      @EndUserText.label: 'Game name'
      @UI.hidden: true
      M.GameName,
      @EndUserText.label: 'Latest game'
      @Consumption.filter.defaultValue: 'Yes'
      @Consumption.valueHelpDefinition: [{ entity: { name: 'ZC_SCELatestGameVH', element: 'LatestGame' } }]
      @UI.selectionField: [{ position: 10 }]
      M.LatestGame,
      // a division is one player in one game; the name compares a player across games
      @EndUserText.label: 'Player in game'
      @ObjectModel.text.element: [ 'PlayerName' ]
      @UI.textArrangement: #TEXT_ONLY
      @Consumption.valueHelpDefinition: [{ entity: { name: 'ZC_SCEPlayerVH', element: 'DivisionUUID' } }]
      @UI.selectionField: [{ position: 30 }]
      @UI.lineItem: [{ position: 20 }]
      M.DivisionUUID,
      @EndUserText.label: 'Player'
      @UI.hidden: true
      M.PlayerName,
      @EndUserText.label: 'Race'
      @ObjectModel.text.element: [ 'Race' ]
      @UI.textArrangement: #TEXT_ONLY
      @Consumption.valueHelpDefinition: [{ entity: { name: 'ZC_SCERaceVH', element: 'CompanyCode' } }]
      @UI.selectionField: [{ position: 40 }]
      M.CompanyCode,
      @EndUserText.label: 'Race name'
      @UI.hidden: true
      M.Race,
      @EndUserText.label: 'Outpost'
      M.PlantCode,
      @EndUserText.label: 'Game second'
      @UI.hidden: true
      M.GameSeconds,
      @EndUserText.label: 'Minute'
      @UI.lineItem: [{ position: 30 }]
      M.GameMinute,
      @EndUserText.label: 'Movement type'
      @ObjectModel.text.element: [ 'MovementTypeText' ]
      @UI.textArrangement: #TEXT_ONLY
      @Consumption.valueHelpDefinition: [{ entity: { name: 'ZC_SCEMovementTypeVH', element: 'MovementType' } }]
      @UI.selectionField: [{ position: 50 }]
      @UI.lineItem: [{ position: 40 }]
      M.MovementType,
      @EndUserText.label: 'Movement type text'
      @UI.hidden: true
      M.MovementTypeText,
      @EndUserText.label: 'Material'
      @Consumption.valueHelpDefinition: [{ entity: { name: 'ZC_SCEMaterialVH', element: 'Material' } }]
      @UI.selectionField: [{ position: 70 }]
      @UI.lineItem: [{ position: 50 }]
      M.Material,
      @EndUserText.label: 'Category'
      @Consumption.valueHelpDefinition: [{ entity: { name: 'ZC_SCECategoryVH', element: 'Category' } }]
      @UI.selectionField: [{ position: 60 }]
      @UI.lineItem: [{ position: 60 }]
      M.Category,
      @EndUserText.label: 'Source'
      M.EventSource,
      @EndUserText.label: 'Quantity'
      @Aggregation.default: #SUM
      @UI.lineItem: [{ position: 70 }]
      M.Quantity,
      @EndUserText.label: 'Mineral currency'
      @UI.hidden: true
      M.MineralCurrency,
      @EndUserText.label: 'Minerals'
      @Aggregation.default: #SUM
      @Semantics.amount.currencyCode: 'MineralCurrency'
      @UI.lineItem: [{ position: 80 }]
      M.Minerals,
      @EndUserText.label: 'Gas currency'
      @UI.hidden: true
      M.GasCurrency,
      @EndUserText.label: 'Gas'
      @Aggregation.default: #SUM
      @Semantics.amount.currencyCode: 'GasCurrency'
      @UI.lineItem: [{ position: 90 }]
      M.Gas,
      // minerals + gas at rate M, defined once in ZI_SCEMovementValueMin (shared with Score over time)
      @EndUserText.label: 'Value (MIN)'
      @Aggregation.default: #SUM
      @Semantics.amount.currencyCode: 'MineralCurrency'
      @UI.lineItem: [{ position: 100 }]
      V.ValueMin
}
