@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'SCE Division'
define view entity ZI_SCEDivision
  as select from zsce_division
  association        to parent ZI_SCEGame     as _Game         on $projection.GameUUID = _Game.GameUUID
  composition [0..*] of ZI_SCEPlant           as _Plant
  composition [0..*] of ZI_SCEProdOrder       as _ProdOrder
  composition [0..*] of ZI_SCEEvent           as _Event
  composition [0..*] of ZI_SCEPIR             as _Requirement
  composition [0..*] of ZI_SCEPlannedOrder    as _PlannedOrder
  composition [0..*] of ZI_SCENotification    as _Notification
  composition [0..*] of ZI_SCEMaintOrder      as _MaintOrder
  association [0..1] to ZI_SCECompany         as _Company      on $projection.CompanyCode = _Company.CompanyCode
  association [0..*] to ZI_SCEStockBalance    as _StockBalance on $projection.DivisionUUID = _StockBalance.DivisionUUID
  association [0..1] to ZI_SCEDivisionNetWorth as _NetWorth    on $projection.DivisionUUID = _NetWorth.DivisionUUID
{
  key division_uuid as DivisionUUID,
      game_uuid     as GameUUID,
      bukrs         as CompanyCode,
      division_code as DivisionCode,
      player_name   as PlayerName,
      game_result   as GameResult,
      _Game,
      _Plant,
      _ProdOrder,
      _Event,
      _Requirement,
      _PlannedOrder,
      _Notification,
      _MaintOrder,
      _Company,
      _StockBalance,
      _NetWorth
}
