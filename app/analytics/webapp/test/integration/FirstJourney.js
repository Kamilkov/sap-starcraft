sap.ui.define([
    "sap/ui/test/opaQunit",
    "./pages/JourneyRunner"
], function (opaTest, runner) {
    "use strict";

    function journey() {
        QUnit.module("First journey");

        opaTest("Start application", function (Given, When, Then) {
            Given.iStartMyApp();

            Then.onTheMovementAnalysisList.iSeeThisPage();
            Then.onTheMovementAnalysisList.onFilterBar().iCheckFilterField("Movement type");
            Then.onTheMovementAnalysisList.onTable().iCheckColumns(3, {"GameMinute":{"header":"Minute"},"MovementType":{"header":"Movement type"},"Minerals":{"header":"Minerals"}});

        });


        opaTest("Navigate to ObjectPage", function (Given, When, Then) {
            // Note: this test will fail if the ListReport page doesn't show any data
            
            When.onTheMovementAnalysisList.onFilterBar().iExecuteSearch();
            
            Then.onTheMovementAnalysisList.onTable().iCheckRows();

            When.onTheMovementAnalysisList.onTable().iPressRow(0);
            Then.onTheMovementAnalysisObjectPage.iSeeThisPage();

        });

        opaTest("Teardown", function (Given, When, Then) { 
            // Cleanup
            Given.iTearDownMyApp();
        });
    }

    runner.run([journey]);
});