sap.ui.define([
    "sap/fe/test/JourneyRunner",
	"zsce/score/test/integration/pages/ScoreList",
	"zsce/score/test/integration/pages/ScoreObjectPage"
], function (JourneyRunner, ScoreList, ScoreObjectPage) {
    'use strict';

    var runner = new JourneyRunner({
        launchUrl: sap.ui.require.toUrl('zsce/score') + '/test/flpSandbox.html#zscescore-tile',
        pages: {
			onTheScoreList: ScoreList,
			onTheScoreObjectPage: ScoreObjectPage
        },
        async: true
    });

    return runner;
});

