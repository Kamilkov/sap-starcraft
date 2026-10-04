@AccessControl.authorizationCheck: #CHECK
@EndUserText.label: 'SCE Company'
define root view entity ZI_SCECompany
  as select from zsce_company
  association [0..*] to ZI_SCEDivision as _Division on $projection.CompanyCode = _Division.CompanyCode
{
  key company_uuid as CompanyUUID,
      bukrs        as CompanyCode,
      butxt        as CompanyName,
      race         as Race,
      @Semantics.systemDateTime.lastChangedAt: true
      last_changed_at as LastChangedAt,
      _Division
}
