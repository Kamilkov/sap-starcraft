@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'SCE Buildable Material per Division'
define view entity ZI_SCEBuildableMaterial
  as select from ZI_SCEDivision as Division
    inner join      ZI_SCEMaterial      as Material    on Material.CompanyCode = Division.CompanyCode
    left outer join ZI_SCEDivisionStock as Producer    on  Producer.DivisionUUID = Division.DivisionUUID
                                                       and Producer.Material     = Material.ProducedBy
    left outer join ZI_SCEDivisionStock as Requirement on  Requirement.DivisionUUID = Division.DivisionUUID
                                                       and Requirement.Material     = Material.Prerequisite
    left outer join ZI_SCEDivisionStock as Minerals    on  Minerals.DivisionUUID = Division.DivisionUUID
                                                       and Minerals.Material     = 'MINERAL'
    left outer join ZI_SCEDivisionStock as Gas         on  Gas.DivisionUUID = Division.DivisionUUID
                                                       and Gas.Material     = 'VESPENE'
{
  key Division.DivisionUUID,
  key Material.Material,
      Material.CompanyCode,
      Material.Category,
      Material.MineralCost,
      Material.GasCost,
      Material.SupplyCost,
      Material.ProducedBy,
      Material.Prerequisite,
      coalesce( Minerals.OnHand, 0 )    as MineralsOnHand,
      coalesce( Gas.OnHand, 0 )         as GasOnHand,
      coalesce( Producer.OnHand, 0 )    as ProducerOnHand,
      coalesce( Requirement.OnHand, 0 ) as PrerequisiteOnHand,
      case
        when Material.ProducedBy   <> '' and coalesce( Producer.OnHand, 0 )    < 1 then ''
        when Material.Prerequisite <> '' and coalesce( Requirement.OnHand, 0 ) < 1 then ''
        when Material.MineralCost > coalesce( Minerals.OnHand, 0 )                then ''
        when Material.GasCost     > coalesce( Gas.OnHand, 0 )                     then ''
        else 'X'
      end                               as Buildable
}
