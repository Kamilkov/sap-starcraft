@EndUserText.label: 'Category'
@AccessControl.authorizationCheck: #CHECK
@ObjectModel.dataCategory: #VALUE_HELP
@ObjectModel.resultSet.sizeCategory: #XS
define view entity ZC_SCECategoryVH
  as select distinct from ZI_SCEMovementAnalysis
{
      @EndUserText.label: 'Category'
  key Category
}
// an unknown material has no category: no empty key in the dropdown
where Category is not null
