@EndUserText.label: 'Race'
@AccessControl.authorizationCheck: #CHECK
@ObjectModel.dataCategory: #VALUE_HELP
@ObjectModel.resultSet.sizeCategory: #XS
define view entity ZC_SCERaceVH
  as select distinct from ZI_SCEMovementAnalysis
{
      @EndUserText.label: 'Race'
      @ObjectModel.text.element: [ 'Race' ]
      @UI.textArrangement: #TEXT_ONLY
  key CompanyCode,
      @EndUserText.label: 'Race name'
      Race
}
