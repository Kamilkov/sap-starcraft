@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'SCE Score per player and game minute'
define view entity ZI_SCEScore
  as select from ZI_SCEScoreMinute      as G
    inner join   ZI_SCEMovementAnalysis as E on  E.DivisionUUID = G.DivisionUUID
                                             and E.GameMinute  <= G.GameMinute
    inner join   ZI_SCEMovementValueMin as V on  V.EventUUID    = E.EventUUID
{
  key G.DivisionUUID,
  key G.GameMinute,
      E.GameUUID,
      E.GameName,
      E.LatestGame,
      E.PlayerName,
      E.CompanyCode,
      E.Race,
      // running totals through the end of G.GameMinute; stock curves signed as ZI_SCEStockBalance (261 and 551 subtract)
      sum( case when E.Category = 'UNIT' and E.Material <> 'SCV'
                then case E.MovementType when '261' then 0 - V.ValueMin
                                         when '551' then 0 - V.ValueMin
                                         else V.ValueMin end
                else 0 end )                                            as ArmyValue,
      sum( case when E.Material = 'SCV'
                then case E.MovementType when '261' then 0 - E.Quantity
                                         when '551' then 0 - E.Quantity
                                         else E.Quantity end
                else 0 end )                                            as Workers,
      sum( case when E.Category = 'RAW'
                then case E.MovementType when '261' then 0 - E.Minerals
                                         when '551' then 0 - E.Minerals
                                         else E.Minerals end
                else 0 end )                                            as BankMinerals,
      sum( case when E.Category = 'RAW'
                then case E.MovementType when '261' then 0 - E.Gas
                                         when '551' then 0 - E.Gas
                                         else E.Gas end
                else 0 end )                                            as BankGas,
      sum( case E.MovementType when '501' then V.ValueMin else 0 end ) as Collected,
      sum( case E.MovementType when '551' then V.ValueMin else 0 end ) as Lost
}
group by
  G.DivisionUUID,
  G.GameMinute,
  E.GameUUID,
  E.GameName,
  E.LatestGame,
  E.PlayerName,
  E.CompanyCode,
  E.Race
