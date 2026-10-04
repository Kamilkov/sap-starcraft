@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'SCE Goods Movement Analysis'
define view entity ZI_SCEMovementAnalysis
  as select from    zsce_event       as Event
    inner join      zsce_division    as Division on Division.division_uuid = Event.division_uuid
    inner join      zsce_game        as Game     on Game.game_uuid = Division.game_uuid
    left outer join zsce_company     as Company  on Company.bukrs = Division.bukrs
    left outer join zsce_plant       as Plant    on Plant.plant_uuid = Event.plant_uuid
    left outer join zsce_material    as Material on Material.matnr = Event.matnr
    left outer join ZI_SCELatestGame as Latest   on Latest.CreatedAt = Game.created_at
{
  key Event.event_uuid                                 as EventUUID,
      Game.game_uuid                                   as GameUUID,
      Game.map_name                                    as MapName,
      // e.g. 'AcropolisLE 2026-09-25 11:26' (played-at, UTC): the game's text in filters, charts and value helps
      concat_with_space( Game.map_name,
        concat_with_space(
          concat( concat( concat( substring( tstmp_to_dats( cast( Game.played_at as abap.dec( 15, 0 ) ), 'UTC', $session.client, 'NULL' ), 1, 4 ), '-' ),
                          concat( substring( tstmp_to_dats( cast( Game.played_at as abap.dec( 15, 0 ) ), 'UTC', $session.client, 'NULL' ), 5, 2 ), '-' ) ),
                  substring( tstmp_to_dats( cast( Game.played_at as abap.dec( 15, 0 ) ), 'UTC', $session.client, 'NULL' ), 7, 2 ) ),
          concat( concat( substring( tstmp_to_tims( cast( Game.played_at as abap.dec( 15, 0 ) ), 'UTC', $session.client, 'NULL' ), 1, 2 ), ':' ),
                  substring( tstmp_to_tims( cast( Game.played_at as abap.dec( 15, 0 ) ), 'UTC', $session.client, 'NULL' ), 3, 2 ) ), 1 ),
        1 )                                            as GameName,
      tstmp_to_dats( cast( Game.played_at as abap.dec( 15, 0 ) ), 'UTC', $session.client, 'NULL' ) as PlayedDate,
      tstmp_to_tims( cast( Game.played_at as abap.dec( 15, 0 ) ), 'UTC', $session.client, 'NULL' ) as PlayedTime,
      cast( case when Latest.CreatedAt is not null then 'Yes' else 'No' end as abap.char( 3 ) )  as LatestGame,
      Division.division_uuid                           as DivisionUUID,
      Division.player_name                             as PlayerName,
      Division.bukrs                                   as CompanyCode,
      Company.race                                     as Race,
      Plant.plant_code                                 as PlantCode,
      Event.game_seconds                               as GameSeconds,
      div( Event.game_seconds, 60 )                    as GameMinute,
      Event.mvt_type                                   as MovementType,
      cast( case Event.mvt_type when '561' then 'Opening stock (561)'
                                when '501' then 'Mining (501)'
                                when '261' then 'Consumption (261)'
                                when '262' then 'Reversal (262)'
                                when '101' then 'Receipt (101)'
                                when '551' then 'Loss (551)'
                                else Event.mvt_type end as abap.char( 20 ) ) as MovementTypeText,
      Event.matnr                                      as Material,
      Material.category                                as Category,
      Event.event_source                               as EventSource,
      Event.quantity                                   as Quantity,
      cast( 'MIN' as waers )                           as MineralCurrency,
      cast( Event.mineral_value as abap.dec( 15, 0 ) ) as Minerals,
      cast( 'GAS' as waers )                           as GasCurrency,
      cast( Event.gas_value as abap.dec( 15, 0 ) )     as Gas
}
