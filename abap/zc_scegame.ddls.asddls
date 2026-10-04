@EndUserText.label: 'SCE Game'
@AccessControl.authorizationCheck: #CHECK
@Metadata.allowExtensions: true
@Search.searchable: true
@UI.headerInfo: { typeName: 'Game', typeNamePlural: 'Games', title: { value: 'MapName' }, description: { value: 'PlayedAt' } }
define root view entity ZC_SCEGame
  provider contract transactional_query
  as projection on ZI_SCEGame
  association [0..*] to ZC_SCEDivisionFinance as _Finance on _Finance.GameUUID = $projection.GameUUID
{
      @UI.facet: [{ id: 'Divisions', type: #LINEITEM_REFERENCE,            targetElement: '_Division',                              label: 'Divisions', position: 10 },
                  { id: 'Finance',   type: #PRESENTATIONVARIANT_REFERENCE, targetElement: '_Finance',  targetQualifier: 'ByPlayer', label: 'Finance',   position: 20 }]
  key GameUUID,
      ReplayHash,
      @UI.lineItem: [{ position: 10 }]
      @UI.selectionField: [{ position: 10 }]
      @Search.defaultSearchElement: true
      @EndUserText.label: 'Map'
      MapName,
      @UI.lineItem: [{ position: 20 }]
      @EndUserText.label: 'Played at'
      PlayedAt,
      @UI.lineItem: [{ position: 30 }]
      @EndUserText.label: 'Duration (s)'
      DurationSeconds,
      WinnerDivisionUUID,
      CreatedAt,
      LastChangedAt,
      _Division : redirected to composition child ZC_SCEDivision,
      _Finance
}
