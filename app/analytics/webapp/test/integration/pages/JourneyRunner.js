sap.ui.define([
    "sap/fe/test/JourneyRunner",
	"zsce/analytics/test/integration/pages/MovementAnalysisList",
	"zsce/analytics/test/integration/pages/MovementAnalysisObjectPage"
], function (JourneyRunner, MovementAnalysisList, MovementAnalysisObjectPage) {
    'use strict';

    var runner = new JourneyRunner({
        launchUrl: sap.ui.require.toUrl('zsce/analytics') + '/test/flpSandbox.html#zsceanalytics-tile',
        pages: {
			onTheMovementAnalysisList: MovementAnalysisList,
			onTheMovementAnalysisObjectPage: MovementAnalysisObjectPage
        },
        async: true
    });

    return runner;
});

