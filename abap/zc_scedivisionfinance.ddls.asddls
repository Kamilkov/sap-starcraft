@EndUserText.label: 'SCE Division Finance'
@AccessControl.authorizationCheck: #CHECK
@UI.headerInfo: { typeName: 'Finance', typeNamePlural: 'Finance' }
@UI.presentationVariant: [
  { qualifier: 'ByPlayer',
    sortOrder: [{ by: 'PlayerName', direction: #ASC }, { by: 'Currency', direction: #DESC }],
    visualizations: [{ type: #AS_LINEITEM }] },
  { qualifier: 'AcrossGames',
    sortOrder: [{ by: 'PlayedAt', direction: #DESC }, { by: 'PlayerName', direction: #ASC }, { by: 'Currency', direction: #DESC }],
    visualizations: [{ type: #AS_LINEITEM, qualifier: 'AcrossGames' }] } ]
define view entity ZC_SCEDivisionFinance
  as select from ZI_SCEDivisionFinance
{
  key DivisionUUID,
  key Currency,
      _Division.GameUUID       as GameUUID,
      _Division.CompanyCode    as CompanyCode,
      @EndUserText.label: 'Map'
      @UI.lineItem: [{ position: 10, qualifier: 'AcrossGames' }]
      _Division._Game.MapName  as MapName,
      @EndUserText.label: 'Played at'
      @UI.lineItem: [{ position: 20, qualifier: 'AcrossGames' }]
      _Division._Game.PlayedAt as PlayedAt,
      @EndUserText.label: 'Player'
      @UI.lineItem: [{ position: 10 }, { position: 30, qualifier: 'AcrossGames' }]
      _Division.PlayerName     as PlayerName,
      @EndUserText.label: 'Opening'
      @UI.lineItem: [{ position: 20 }, { position: 40, qualifier: 'AcrossGames' }]
      Opening,
      @EndUserText.label: 'Mined'
      @UI.lineItem: [{ position: 30 }, { position: 50, qualifier: 'AcrossGames' }]
      Mined,
      @EndUserText.label: 'Lost'
      @UI.lineItem: [{ position: 40 }, { position: 60, qualifier: 'AcrossGames' }]
      Lost,
      @EndUserText.label: 'Scrap'
      @UI.lineItem: [{ position: 45 }, { position: 65, qualifier: 'AcrossGames' }]
      Scrap,
      @EndUserText.label: 'Maintenance'
      @UI.lineItem: [{ position: 47 }, { position: 67, qualifier: 'AcrossGames' }]
      Maintenance,
      @EndUserText.label: 'Net worth'
      @UI.lineItem: [{ position: 50 }, { position: 70, qualifier: 'AcrossGames' }]
      NetWorth,
      @EndUserText.label: 'On hand'
      @UI.lineItem: [{ position: 60 }, { position: 80, qualifier: 'AcrossGames' }]
      OnHand,
      @EndUserText.label: 'Assets'
      @UI.lineItem: [{ position: 70 }, { position: 90, qualifier: 'AcrossGames' }]
      Assets,
      @EndUserText.label: 'Army'
      @UI.lineItem: [{ position: 80 }, { position: 100, qualifier: 'AcrossGames' }]
      Army,
      @EndUserText.label: 'WIP'
      @UI.lineItem: [{ position: 90 }, { position: 110, qualifier: 'AcrossGames' }]
      WIP
}
