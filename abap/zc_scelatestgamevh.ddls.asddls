@EndUserText.label: 'Latest game'
@AccessControl.authorizationCheck: #CHECK
@ObjectModel.dataCategory: #VALUE_HELP
@ObjectModel.resultSet.sizeCategory: #XS
define view entity ZC_SCELatestGameVH
  as select distinct from ZI_SCEMovementAnalysis
{
      @EndUserText.label: 'Latest game'
  key LatestGame
}
