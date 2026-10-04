@EndUserText.label: 'Score over time'
@AccessControl.authorizationCheck: #CHECK
@OData.applySupportedForAggregation: #FULL
@UI.headerInfo: { typeName: 'Score', typeNamePlural: 'Scores' }
// series Game and Player: a replay holds two players per game, and #MAX would merge them into one line
@UI.chart: [{ qualifier: 'ArmyAndLosses', title: 'Army and losses', chartType: #LINE,
              dimensions: [ 'GameMinute', 'GameUUID', 'DivisionUUID' ], measures: [ 'ArmyValue', 'Lost' ],
              dimensionAttributes: [{ dimension: 'GameMinute', role: #CATEGORY }, { dimension: 'GameUUID', role: #SERIES },
                                    { dimension: 'DivisionUUID', role: #SERIES }],
              measureAttributes: [{ measure: 'ArmyValue', role: #AXIS_1 }, { measure: 'Lost', role: #AXIS_1 }] },
            { qualifier: 'KpiCollected', title: 'Collected', chartType: #LINE,
              dimensions: [ 'GameMinute', 'DivisionUUID' ], measures: [ 'Collected' ],
              dimensionAttributes: [{ dimension: 'GameMinute', role: #CATEGORY }, { dimension: 'DivisionUUID', role: #SERIES }],
              measureAttributes: [{ measure: 'Collected', role: #AXIS_1 }] },
            { qualifier: 'KpiArmy', title: 'Army value', chartType: #LINE,
              dimensions: [ 'GameMinute', 'DivisionUUID' ], measures: [ 'ArmyValue' ],
              dimensionAttributes: [{ dimension: 'GameMinute', role: #CATEGORY }, { dimension: 'DivisionUUID', role: #SERIES }],
              measureAttributes: [{ measure: 'ArmyValue', role: #AXIS_1 }] },
            { qualifier: 'KpiLost', title: 'Lost', chartType: #LINE,
              dimensions: [ 'GameMinute', 'DivisionUUID' ], measures: [ 'Lost' ],
              dimensionAttributes: [{ dimension: 'GameMinute', role: #CATEGORY }, { dimension: 'DivisionUUID', role: #SERIES }],
              measureAttributes: [{ measure: 'Lost', role: #AXIS_1 }] }]
@UI.presentationVariant: [{ sortOrder: [{ by: 'GameMinute', direction: #ASC }],
                            visualizations: [{ type: #AS_CHART, qualifier: 'ArmyAndLosses' }, { type: #AS_LINEITEM }] },
                          { qualifier: 'KpiCollected', sortOrder: [{ by: 'GameMinute', direction: #ASC }],
                            visualizations: [{ type: #AS_CHART, qualifier: 'KpiCollected' }] },
                          { qualifier: 'KpiArmy', sortOrder: [{ by: 'GameMinute', direction: #ASC }],
                            visualizations: [{ type: #AS_CHART, qualifier: 'KpiArmy' }] },
                          { qualifier: 'KpiLost', sortOrder: [{ by: 'GameMinute', direction: #ASC }],
                            visualizations: [{ type: #AS_CHART, qualifier: 'KpiLost' }] }]
// the KPI tags (UI.KPI, UI.SelectionVariant#LatestGameKpi) are in app/score/webapp/annotations/annotation.xml:
// RAP's @UI.kpi output (SelectionVariantQualifier, uppercased filter literals) is not readable by Fiori Elements V4
define view entity ZC_SCEScore
  as select from ZI_SCEScore
{
      // a division is one player in one game
      @EndUserText.label: 'Player in game'
      @ObjectModel.text.element: [ 'PlayerName' ]
      @UI.textArrangement: #TEXT_ONLY
      @Consumption.valueHelpDefinition: [{ entity: { name: 'ZC_SCEPlayerVH', element: 'DivisionUUID' } }]
      @UI.selectionField: [{ position: 30 }]
      @UI.lineItem: [{ position: 20 }]
  key DivisionUUID,
      @EndUserText.label: 'Minute'
      @UI.lineItem: [{ position: 30 }]
  key GameMinute,
      @EndUserText.label: 'Game'
      @ObjectModel.text.element: [ 'GameName' ]
      @UI.textArrangement: #TEXT_ONLY
      @Consumption.valueHelpDefinition: [{ entity: { name: 'ZC_SCEGameVH', element: 'GameUUID' } }]
      @UI.selectionField: [{ position: 20 }]
      @UI.lineItem: [{ position: 10 }]
      GameUUID,
      @EndUserText.label: 'Game name'
      @UI.hidden: true
      GameName,
      @EndUserText.label: 'Latest game'
      @Consumption.filter.defaultValue: 'Yes'
      @Consumption.valueHelpDefinition: [{ entity: { name: 'ZC_SCELatestGameVH', element: 'LatestGame' } }]
      @UI.selectionField: [{ position: 10 }]
      LatestGame,
      @EndUserText.label: 'Player'
      @UI.hidden: true
      PlayerName,
      @EndUserText.label: 'Race'
      @ObjectModel.text.element: [ 'Race' ]
      @UI.textArrangement: #TEXT_ONLY
      @Consumption.valueHelpDefinition: [{ entity: { name: 'ZC_SCERaceVH', element: 'CompanyCode' } }]
      @UI.selectionField: [{ position: 40 }]
      CompanyCode,
      @EndUserText.label: 'Race name'
      @UI.hidden: true
      Race,
      @EndUserText.label: 'Mineral currency'
      @UI.hidden: true
      cast( 'MIN' as waers ) as MineralCurrency,
      @EndUserText.label: 'Gas currency'
      @UI.hidden: true
      cast( 'GAS' as waers ) as GasCurrency,
      // running totals: #MAX, since a sum across minutes means nothing; collapsed, they read as peak or final value
      @EndUserText.label: 'Army value'
      @Aggregation.default: #MAX
      @Semantics.amount.currencyCode: 'MineralCurrency'
      @UI.lineItem: [{ position: 40 }]
      ArmyValue,
      @EndUserText.label: 'Workers'
      @Aggregation.default: #MAX
      @UI.lineItem: [{ position: 50 }]
      Workers,
      @EndUserText.label: 'Bank minerals'
      @Aggregation.default: #MAX
      @Semantics.amount.currencyCode: 'MineralCurrency'
      @UI.lineItem: [{ position: 60 }]
      BankMinerals,
      @EndUserText.label: 'Bank gas'
      @Aggregation.default: #MAX
      @Semantics.amount.currencyCode: 'GasCurrency'
      @UI.lineItem: [{ position: 70 }]
      BankGas,
      @EndUserText.label: 'Collected'
      @Aggregation.default: #MAX
      @Semantics.amount.currencyCode: 'MineralCurrency'
      @UI.lineItem: [{ position: 80 }]
      Collected,
      @EndUserText.label: 'Lost'
      @Aggregation.default: #MAX
      @Semantics.amount.currencyCode: 'MineralCurrency'
      @UI.lineItem: [{ position: 90 }]
      Lost
}
