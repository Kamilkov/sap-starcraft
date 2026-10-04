@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'SCE Game'
define root view entity ZI_SCEGame
  as select from zsce_game
  composition [0..*] of ZI_SCEDivision as _Division
{
  key game_uuid            as GameUUID,
      replay_hash          as ReplayHash,
      map_name             as MapName,
      played_at            as PlayedAt,
      duration_seconds     as DurationSeconds,
      winner_division_uuid as WinnerDivisionUUID,
      @Semantics.systemDateTime.createdAt: true
      created_at           as CreatedAt,
      @Semantics.systemDateTime.lastChangedAt: true
      last_changed_at      as LastChangedAt,
      _Division
}
