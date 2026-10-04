@EndUserText.label: 'Player'
@AccessControl.authorizationCheck: #CHECK
@ObjectModel.dataCategory: #VALUE_HELP
define view entity ZC_SCEPlayerVH
  as select distinct from ZI_SCEMovementAnalysis
{
      @EndUserText.label: 'Player in game'
      @ObjectModel.text.element: [ 'PlayerName' ]
      @UI.textArrangement: #TEXT_ONLY
  key DivisionUUID,
      @EndUserText.label: 'Player'
      PlayerName,
      @EndUserText.label: 'Game'
      GameName
}
