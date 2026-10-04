sap.ui.define([
    "sap/fe/test/JourneyRunner",
	"zsce/game/test/integration/pages/GameList",
	"zsce/game/test/integration/pages/GameObjectPage",
	"zsce/game/test/integration/pages/DivisionObjectPage"
], function (JourneyRunner, GameList, GameObjectPage, DivisionObjectPage) {
    'use strict';

    var runner = new JourneyRunner({
        launchUrl: sap.ui.require.toUrl('zsce/game') + '/test/flpSandbox.html#zscegame-tile',
        pages: {
			onTheGameList: GameList,
			onTheGameObjectPage: GameObjectPage,
			onTheDivisionObjectPage: DivisionObjectPage
        },
        async: true
    });

    return runner;
});

