sap.ui.define(['sap/fe/test/ListReport'], function(ListReport) {
    'use strict';

    var CustomPageDefinitions = {
        actions: {},
        assertions: {}
    };

    return new ListReport(
        {
            appId: 'zsce.game',
            componentId: 'GameList',
            contextPath: '/Game'
        },
        CustomPageDefinitions
    );
});