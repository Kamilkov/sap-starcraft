@EndUserText.label: 'SCE Company'
@AccessControl.authorizationCheck: #CHECK
@Metadata.allowExtensions: true
@Search.searchable: true
@UI.headerInfo: { typeName: 'Company', typeNamePlural: 'Companies', title: { value: 'CompanyName' }, description: { value: 'CompanyCode' } }
define root view entity ZC_SCECompany
  provider contract transactional_query
  as projection on ZI_SCECompany
  association [0..*] to ZC_SCEDivisionFinance as _Finance on _Finance.CompanyCode = $projection.CompanyCode
{
      @UI.facet: [{ id: 'Divisions', type: #LINEITEM_REFERENCE,            targetElement: '_Division',                                 label: 'Divisions across games', position: 10 },
                  { id: 'Finance',   type: #PRESENTATIONVARIANT_REFERENCE, targetElement: '_Finance',  targetQualifier: 'AcrossGames', label: 'Finance across games',   position: 20 }]
  key CompanyUUID,
      @UI.lineItem: [{ position: 10 }]
      @UI.selectionField: [{ position: 10 }]
      @Search.defaultSearchElement: true
      CompanyCode,
      @UI.lineItem: [{ position: 20 }]
      CompanyName,
      @UI.lineItem: [{ position: 30 }]
      Race,
      LastChangedAt,
      _Division : redirected to ZC_SCEDivision,
      _Finance
}
