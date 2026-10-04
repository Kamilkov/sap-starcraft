@EndUserText.label: 'Material'
@AccessControl.authorizationCheck: #CHECK
@ObjectModel.dataCategory: #VALUE_HELP
define view entity ZC_SCEMaterialVH
  as select distinct from ZI_SCEMovementAnalysis
{
      @EndUserText.label: 'Material'
  key Material,
      @EndUserText.label: 'Category'
      Category
}
