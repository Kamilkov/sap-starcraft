@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'SCE Latest Game (newest created)'
define view entity ZI_SCELatestGame
  as select from zsce_game
{
  max( created_at ) as CreatedAt
}
