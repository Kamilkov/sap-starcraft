@EndUserText.label: 'Game'
@AccessControl.authorizationCheck: #CHECK
@ObjectModel.dataCategory: #VALUE_HELP
define view entity ZC_SCEGameVH
  as select distinct from ZI_SCEMovementAnalysis
{
      @EndUserText.label: 'Game'
      @ObjectModel.text.element: [ 'GameName' ]
      @UI.textArrangement: #TEXT_ONLY
  key GameUUID,
      @EndUserText.label: 'Game'
      GameName,
      @EndUserText.label: 'Latest game'
      LatestGame
}
