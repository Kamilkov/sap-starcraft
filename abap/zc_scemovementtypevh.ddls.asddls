@EndUserText.label: 'Movement type'
@AccessControl.authorizationCheck: #CHECK
@ObjectModel.dataCategory: #VALUE_HELP
@ObjectModel.resultSet.sizeCategory: #XS
define view entity ZC_SCEMovementTypeVH
  as select distinct from ZI_SCEMovementAnalysis
{
      @ObjectModel.text.element: [ 'MovementTypeText' ]
      @UI.textArrangement: #TEXT_ONLY
  key MovementType,
      @EndUserText.label: 'Movement type'
      MovementTypeText
}
