@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'SCE Score time axis (player, minute)'
define view entity ZI_SCEScoreMinute
  as select distinct from ZI_SCEMovementAnalysis
{
  key DivisionUUID,
  key GameMinute
}
