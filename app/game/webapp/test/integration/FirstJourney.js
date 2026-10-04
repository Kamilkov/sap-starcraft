sap.ui.define([
    "sap/ui/test/opaQunit",
    "./pages/JourneyRunner"
], function (opaTest, runner) {
    "use strict";

    function journey() {
        QUnit.module("First journey");

        opaTest("Start application", function (Given, When, Then) {
            Given.iStartMyApp();

            Then.onTheGameList.iSeeThisPage();
            Then.onTheGameList.onFilterBar().iCheckFilterField("MapName");
            Then.onTheGameList.onTable().iCheckColumns(3, {"MapName":{"header":"MapName"},"PlayedAt":{"header":"Time Stamp"},"DurationSeconds":{"header":"DurationSeconds"}});

        });


        opaTest("Navigate to ObjectPage", function (Given, When, Then) {
            // Note: this test will fail if the ListReport page doesn't show any data
            
            When.onTheGameList.onFilterBar().iExecuteSearch();
            
            Then.onTheGameList.onTable().iCheckRows();

            When.onTheGameList.onTable().iPressRow(0);
            Then.onTheGameObjectPage.iSeeThisPage();

        });

        opaTest("Teardown", function (Given, When, Then) { 
            // Cleanup
            Given.iTearDownMyApp();
        });
    }

    runner.run([journey]);
});