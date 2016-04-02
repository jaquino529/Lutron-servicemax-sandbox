/**
  * @author Jorge Aquino/Forefront
  * @version 1.0
  * @description
  *
  * PURPOSE
  *
  *    This class handles all trigger actions for Quote_Order (QTT_Order__c)
  *
  * TEST CLASS
  *
  *    Name of the test class
  *    For Naming use the class Quote_OrderTriggerHandler_TEST
  *
  * ENTRY POINTS
  *
  *    Called from Quote_OrderTrigger
  *
  * CHANGE LOG
  *
  *    [Version; Date; Author; Description]
  *    v1.0; 11/19/2015;  Jorge Aquino;Forefront; Initial Build
  *          11/24/2015;  Jorge Aquino;ForeFront; refactor logic in orderedRevSetter method to better handle 50000+ rows returned from query
  *          11/25/2015;  Jorge Aquino;ForeFront; assign proper Location when creating Master Work Orders
  *          12/09/2015;  Jorge Aquino;ForeFront; modify setStandardLocationName to not allow loc names > 80 characters
  *          12/14/2015;  Faraz Khan;ForeFront; create two types of contracts from Quote Order and respective fields. Then create Covered Products and Covered Locations
  *          12/15/2015;  Faraz Khan;ForeFront; Fields in CoveredProducts and Covered location are populated.
  *          12/30/2015;  Jorge Aquino;ForeFront; modified syncOppFromQuoteOrder to only update if values have changed
  *          1/9/2016;    Jorge Aquino;ForeFront; modified createJob method to set the Job owner same as the QuoteOrder owner;
  *                                               added setQuoteOrderOwner method to set the owner same as the Opportunity owner;
  *                                               modified createReleaseZeroData method to prevent duplicate Jobs when
  *                                               more than 1 quote for the same new job is updated in one batch
  *          1/11/2016;   Jorge Aquino;ForeFront; added setPrimarySystem method, called from beforeInsert and beforeUpdate.
  *          1/13/2016;   Jorge Aquino;ForeFront; fixed issue where multiple Installed Products were being created for 1 MWO;
  *                                               fixed issue where duplicate Work Orders were being created for Release0 and Release1
  *          1/18/2016;   Jorge Aquino;ForeFront; added logic in createReleaseZeroData method to populate IFS notes when creating/updating Jobs
  *          1/24/2016;   Jorge Aquino;ForeFront; fixed issue if QuoteOrder goes to Partial or Released without going to HFR first, then "Job missing" error was occuring;
  *                                               changed syncOppFromQuoteOrder to handle a blank QuoteOrder stage properly;
  *                                               moved logic that created contracts to a new method, autoGenContracts(Set<ID> qOIDs), and modified it to get the Service Plan
  *                                               by ProductId, removed all use of the Service Plan lookup on Product2, as that field is to be deprecated. 
  *          1/26/2016;   Jorge Aquino;ForeFront; updated method syncOppFromQuoteOrder to sync QuoteOrder.Job Name to Opportunity.Project Name
  *                                               and sync new field QuoteOrder.ProjectID to Opportunity.Job Number.
  *          1/26/2016;   Jorge Aquino;ForeFront; fixed issue in autoGenContracts(Set<ID> qOIDs) where the MWO lookup on the Contract was not being polulated;
  *                                               also fixed it to not produce duplicate contracts when QuoteOrder is updated
  *          1/27/2016    Jorge Aquino;ForeFront; modifications in syncOppFromQuoteOrder method: sync Opp Amount from QuoteOrder Blanket Value only if it is "ordered";
  *                                               set the Opp name only when creating an opportunity, don't sync on update; set [Opp.Name] from [QuoteOrder.Quote Order Name]
  *                                               set the Opp.Stage only when creating an Opp or when QuoteOrder.Stage = 'Won - Hold For Release' or 'Won- Released' 
  *          1/28/2016    Jorge Aquino;ForeFront; added new method, SetCurrency(QTT_Order__c qOrd); method is called from handleBeforeInsert & handleBeforeUpdate
  *          2/3/2016     Jorge Aquino;ForeFront; syncOppFromQuoteOrder() method: per new requirements, removed the update of Opp Account; added setting the Opp Account = QuoteOrder Account;
  *                                               added setting Opp CreatedFromQTTIntegration = true when creating a new Opp
  *          2/4/2016     Jorge Aquino;ForeFront; revised unlinkOppsFromQuoteOrders() to handle resetting opportunity fields when a previously linked QuoteOrder is linked to another Opportunity
  *          2/12/2016    Jorge Aquino;ForeFront; changed cancelOrder() method to call resetOpportunityValuesForCancelledOrders() for (LS-341 New Requirements 2/8/16)
  *          2/19/2016    Jorge Aquino;ForeFront; 1. added boolean parameter 'firstTimeLink' to syncOppFromQuoteOrder() to handle different business requirements when linking a quote to an opportunity
  *                                               for the first time vs synching an opportunity that is already linked;
  *                                               2. changed syncOppFromQuoteOrder() per new requirements: Update the following fields with the QTT value ONLY IF THEY ARE BLANK IN SFDC: Construction Type,Vertical Market, Installation Type;
  *                                               3. changed syncOppFromQuoteOrder() per new requirements: remove update of Opportunity fields: Lutron_Rep__c & Share_with_Lutron_Rep__c
  *                                               4. new method unlinkRevisionsFromOpportunities() was added to unlinkOppsFromQuoteOrders() to handle new requirements: "Remove Quote Revisions information" & "Remove Quoted To as Partner Account" 
  *          2/22/2016    Jorge Aquino;ForeFront; New requirements when unlinking Opportunities from QuoteOrders to set specific Opportunity field values back to what they were when the QuoteOrder was linked to the Opportunity:
  *                                               1. added new method linkQuotesToOpportunities() to handle logic for creating new custom object, Opportunity_Link_History__c when a QuoteOrder is linked
  *                                               2. changed getOppsRelatedToQuoteOrders() to get related records from new custom object, Opportunity_Link_History__c along with each Opportunity
  *                                               3. changed unlinkOppsFromQuoteOrders() to set specific Opportunity fields to previous values based on new requirements
  *          2/28/2016    Jorge Aquino/ForeFront; LS-396; refactor due to adding a lookup from MWO to Installed Product and removing the lookup from Installed Product to MWO.
  *                                               1. changed createUpdateMasterWorkOrders() to populate the new lookup from MWO to Installed Product
  *                                               2. changed autoGenContracts() to use the new lookup field on the MWO when creating a new Covered Product
  *                                               3. fixed bug in autoGenContracts() where the Location field was not being populated on the Covered Location record
  *          3/1/2016     Jorge Aquino/ForeFront; 1. changed unlinkOppsFromQuoteOrders() to set the Parent Opportunity to null
  *                                               2. changed handleAfterInsert() to only send QuoteOrders that are linking to existing Opportunities into syncRelatedOpps()
  *          3/26/2016    Jorge Aquino/ForeFront; For QTT Data Integrity effort, commented out createReleaseWorkorders() in createServiceMaxData() and createReleaseZeroData();
  **/
public class Quote_OrderTriggerHandler {
    //public Quote_OrderTriggerHandler() {}
    
  public static Boolean donotRunCreateSVMXDataMethod = false;

  //List of QTT Order Id
  //Populated by the QTT_Quote_Revision_TriggerUtility
  public static Set<Id> executionQTTIdList = new Set<Id>();
  public static Map<Id, QTT_Quote_Revision__c> executionQTTQuoteRevisionMap = new Map<Id, QTT_Quote_Revision__c>();

  public static void handleBeforeInsert(List<QTT_Order__c> newQuoteOrders){

    System.debug('Quote_OrderTriggerHandler.handleBeforeInsert');

    // define lists of QuoteOrders
    //List<QTT_Order__c> qOrdersForOwner = new List<QTT_Order__c>();
    List<QTT_Order__c> qOrdersToLinkOpp = new List<QTT_Order__c>();
    List<QTT_Order__c> qOrdersForJob = new List<QTT_Order__c>();
    List<QTT_Order__c> qOrdersForNewOpp = new List<QTT_Order__c>();
    List<QTT_Order__c> qOrdersForPrimarySys = new List<QTT_Order__c>();

    // define collections of related identifiers
    //Set<ID> oppIDsForOwner = new Set<ID>();
    Set<String> qttJobNumbers = new Set<String>();
    Set<String> qttStartupModels = new Set<String>();

    // process QuoteOrders to build lists and collections based on what needs to be updated
    for (QTT_Order__c qOrd : newQuoteOrders){

      setCurrency(qOrd); // set the QuoteOrder Currency, converting from QTT Currency to SFDC's CurrencyIsoCode if needed 

      setQuoteOrderStage(qOrd); // set the QuoteOrder Stage

      if (String.isNotBlank(qOrd.QTT_Startup_Model__c)){

        qOrdersForPrimarySys.add(qOrd);
        qttStartupModels.add(qOrd.QTT_Startup_Model__c);
      }

      /*if (String.isNotBlank(qOrd.Opportunity__c)){ // if the QuoteOrder has an opportunity

        qOrdersForOwner.add(qOrd); // add it to the list
        oppIDsForOwner.add(qOrd.Opportunity__c);
      }*/

      if (String.isNotBlank(qOrd.Opportunity__c)){ // if the QuoteOrder has an opportunity

        qOrdersToLinkOpp.add(qOrd); // add this QuoteOrder to the list to link Opportunities
      }

      if (String.isNotBlank(qOrd.QTT_Job_Number__c)){ // if the QuoteOrder has a Job#

        qOrdersForJob.add(qOrd); // add it to the list
        qttJobNumbers.add(qOrd.QTT_Job_Number__c);
      }

      if (String.isNotBlank(qOrd.QTT_Opportunity_RID__c) && String.isBlank(qOrd.Opportunity__c)){ // if the QuoteOrder needs a new Opportunity

        qOrd.QuoteOrder_Created_Opportunity__c = true;
        qOrdersForNewOpp.add(qOrd); // add it to the list
      }
    }

    // set the primary system of the QuoteOrder
    if (qOrdersForPrimarySys.size() > 0){
      setPrimarySystem(qOrdersForPrimarySys,qttStartupModels);
    }

    /*// set the owner of the QuoteOrder to be same as the related Opportunity
    if (qOrdersForOwner.size() > 0){
      System.debug('newQuoteOrders: '+newQuoteOrders);
      setQuoteOrderOwner(qOrdersForOwner,oppIDsForOwner);
    }*/

    if (! qOrdersToLinkOpp.isEmpty()){ // if there are QuoteOrders to link to Opportunities

      linkQuotesToOpportunities(qOrdersToLinkOpp); // liknk the QuoteOrders to the Opportunities
    }

    // set Job Number lookup on quote orders if related Jobs found
    if (qOrdersForJob.size() > 0){
      System.debug('newQuoteOrders: '+newQuoteOrders);
      setJobNumber(qOrdersForJob,qttJobNumbers);
    }

    // create new Opportunities for QuoteOrders that require it
    if (qOrdersForNewOpp.size() > 0){
      System.debug('newQuoteOrders: '+newQuoteOrders);
      createOppsForQuoteOrders(qOrdersForNewOpp);
    }
  }

  public static void handleBeforeUpdate(Map<ID, QTT_Order__c> old_Map, Map<ID, QTT_Order__c> new_Map){
    // 1/23/16 J. Aquino/ForeFront; system.debug('checkRecursive.runOnceBeforeUpdate() is: ' + checkRecursive.runOnceBeforeUpdate());
    if (! checkRecursive.runOnceBeforeUpdate()){ // prevent recursive calls
      system.debug('checkRecursive.runOnceBeforeUpdate() is False');
      return;
    } else {
      system.debug('checkRecursive.runOnceBeforeUpdate() is True');
    }
    System.debug('Quote_OrderTriggerHandler.handleBeforeUpdate');

    System.debug('Triggers are not disabled');

    // set list of new quote orders from map values
    List<QTT_Order__c> updatedQuoteOrderList = new_Map.values();

    // define list of quote orders where Job Number has changed
    List<QTT_Order__c> qOrdersToUpdateJob = new List<QTT_Order__c>();

    // define collection of changed Job Numbers
    Set<String> jNumbers = new Set<String>();

    // define list of quote orders where Opportunity needs to be unlinked
    List<QTT_Order__c> qOrdersToUnlinkOpp = new List<QTT_Order__c>(); 

    // define list of quote orders where Opportunity needs to be linked
    List<QTT_Order__c> qOrdersToLinkOpp = new List<QTT_Order__c>();

    // define list of quote orders where new Opportunity needs to be created
    List<QTT_Order__c> qOrdersToCreateOpp = new List<QTT_Order__c>();

    // define map of quote orders that need to have the ordered revision lookup populated
    Map<ID,QTT_Order__c> qOrdsForRevision = new Map<ID,QTT_Order__c>();

    // define list of quote orders where Startup Model (QTT System Type) has changed
    List<QTT_Order__c> qOrdersForPrimarySys = new List<QTT_Order__c>();

    // define collection of changed Startup Models
    Set<String> qttStartupModels = new Set<String>();

    // process quote orders
    for (ID qOID : new_Map.keySet()){

      // get new and old instances of the quote order
      QTT_Order__c oldQ = old_Map.get(qOID);
      QTT_Order__c newQ = new_Map.get(qOID);

      setCurrency(newQ); // set the QuoteOrder Currency, converting from QTT Currency to SFDC's CurrencyIsoCode if needed 

      setQuoteOrderStage(newQ); // set the QuoteOrder Stage

      System.debug(oldQ);
      System.debug(newQ);
      // if the ordered revision lookup needs to be set, add the quote order to the map
     if ( (newQ.QTT_Ordered_Rev__c != oldQ.QTT_Ordered_Rev__c) || (String.isNotBlank(newQ.QTT_Ordered_Rev__c) && String.isBlank(newQ.Ordered_Revision__c) ) ){

          qOrdsForRevision.put(newQ.Id, newQ);
      }

      // check if Job Lookup needs to be set or reset
      if ((newQ.QTT_Job_Number__c != oldQ.QTT_Job_Number__c) || (String.isNotBlank(newQ.QTT_Job_Number__c) && String.isBlank(newQ.Job_Number__c))){

        qOrdersToUpdateJob.add(newQ);
        jNumbers.add(newQ.QTT_Job_Number__c);
      }

      // check if Primary System needs to be set or reset
      if ((newQ.QTT_Startup_Model__c != oldQ.QTT_Startup_Model__c) || (String.isNotBlank(newQ.Primary_System__c) && String.isBlank(newQ.QTT_Startup_Model__c))){

        qOrdersForPrimarySys.add(newQ);
        qttStartupModels.add(newQ.QTT_Startup_Model__c);
      }

      // check if Opportunity needs to be unlinked
      if (newQ.Unlink_QTT_Opportunity_c__c && String.isNotBlank(newQ.Opportunity__c)){ // if this QuoteOrder has received a request to unlink the Opportunity

        qOrdersToUnlinkOpp.add(newQ); // add the QuoteOrder to the list to be unlinked
       
      } else if (String.isNotBlank(oldQ.Opportunity__c) && newQ.Opportunity__c != oldQ.Opportunity__c){ // if this QuoteOrder was linked to an Opp and now is linked to another Opp

        qOrdersToUnlinkOpp.add(oldQ); // add the previous version of the QuoteOrder to the list to be unlinked
        qOrdersToLinkOpp.add(newQ); // add the new version of the QuoteOrder to the list to be linked

      } else if (String.isBlank(oldQ.Opportunity__c) && String.isNotBlank(newQ.Opportunity__c)){ // if QuoteOrder is now being linked to an Opportunity

        qOrdersToLinkOpp.add(newQ); // add the new version of the QuoteOrder to the list to be linked
      }

      // check if opportunity needs to be created
      if (String.isNotBlank(newQ.QTT_Opportunity_RID__c) && String.isBlank(newQ.Opportunity__c)){

        qOrdersToCreateOpp.add(newQ);
        newQ.QuoteOrder_Created_Opportunity__c = true;
      }

      //LS-341; 1/21/16  efuscarino/forefront
      //Check if Order has been cancelled
      if(oldQ.Stage__c != 'Cancelled System Order' && newQ.Stage__c == 'Cancelled System Order'){

        newQ.QTT_Order_Status__c = '';

      }
      System.debug('newQ.StageName__c: '+newQ.StageName__c);
    }

    // if the ordered revision was changed, update the lookup
    if (qOrdsForRevision.size() > 0){

      orderedRevSetter(qOrdsForRevision);
    }

    // set the Job Number lookup on the quote orders
    if (qOrdersToUpdateJob.size() > 0){

      setJobNumber(qOrdersToUpdateJob,jNumbers);
    }

    // set the primary system of the QuoteOrder
    if (qOrdersForPrimarySys.size() > 0){

      setPrimarySystem(qOrdersForPrimarySys,qttStartupModels);
    }

    // unlink Opportunity from QuoteOrder if requested
    if (qOrdersToUnlinkOpp.size() > 0){

      unlinkOppsFromQuoteOrders(qOrdersToUnlinkOpp);
    }

    // link Opportunity from QuoteOrder 
    if (qOrdersToLinkOpp.size() > 0){

      linkQuotesToOpportunities(qOrdersToLinkOpp);
    }

    // create new Opportunities for QuoteOrders that require it
    if (qOrdersToCreateOpp.size() > 0){

      createOppsForQuoteOrders(qOrdersToCreateOpp);
    }
  }

  public static void handleAfterInsert(List<QTT_Order__c> newQuoteOrders){

    System.debug('Quote_OrderTriggerHandler.handleAfterInsert');

    List<QTT_Order__c> qOrdersLinkedToExistingOpps = new List<QTT_Order__c>(); // define list of QuoteOrders that are being linked to existing Opportunities

    for (QTT_Order__c qOrd : newQuoteOrders){  // iterate thru QuoteOrders

      if (! qOrd.QuoteOrder_Created_Opportunity__c && String.isNotBlank(qOrd.Opportunity__c)){ // if the QuoteOrder was linked to an existing Opportunity

        qOrdersLinkedToExistingOpps.add(qOrd); // add the QuoteOrder to the list
      }
    }

    if (! qOrdersLinkedToExistingOpps.isEmpty()){ // if there are QuoteOrders that were linked to existing Opportunities

      Boolean firstTimeLink = true;
      syncRelatedOpps(newQuoteOrders,firstTimeLink); // sync Opportunities with the related QuoteOrders
    }
  }

  public static void handleAfterUpdate(Map<ID, QTT_Order__c> old_Map, Map<ID, QTT_Order__c> new_Map){

    if (! checkRecursive.runOnceAfterUpdate()){ // prevent recursive calls
      return;
    }
    System.debug('Quote_OrderTriggerHandler.handleAfterUpdate');

    // define list of quote orders that need release zero data created (Job, Master Work Order, Location, Installed Product, Work Orders)
    //List<QTT_Order__c> releaseZeroOrders = new List<QTT_Order__c>();
    Set<String> releaseZeroOrderIds = new Set<String>();
    
    Set<String> syncMWOOrderIds = new Set<String>();

    // define a list of model numbers to look up product to get the Service plan.
    List<QTT_Order__c> modelNumbers = new List<QTT_Order__c>();

    // define collection of ids for quote orders that have hit Release1
    Set<String> releaseOneOrderIds = new Set<String>();

    // init collection of ids from all updated quote orders
    Set<ID> qOrderIds = new_Map.keySet();

    // define new and old instances of a quote order
    QTT_Order__c oldQ;

    QTT_Order__c newQ;

    List<QTT_Order__c> cancelledOrders;

    List<QTT_Order__c> ordersForOppSync = new List<QTT_Order__c>(); // list of QuoteOrders to sync with already linked Opportunity
    List<QTT_Order__c> ordersForFirstTimeLink = new List<QTT_Order__c>(); // list of QuoteOrders being linked to an Opportunity for the first time    

    Boolean hasNewOrderLines;

    // process updated quote orders
    for (ID qOID : new_Map.keySet()){

      // get new and old instances of the quote order
      oldQ = old_Map.get(qOID);
      newQ = new_Map.get(qOID);

      hasNewOrderLines = false;
      if (oldQ == null){ // if previous version of QuoteOrder does not exist

        if(newQ.Order_Lines__c > 0){ // if Order Lines exist

          hasNewOrderLines = true; // QuoteOrder has new order lines
        } 
      } else { // if previous version of QuoteOrder exists

        if (newQ.Order_Lines__c > oldQ.Order_Lines__c){ // if new version of QuoteOrder has more lines than previous version

          hasNewOrderLines = true; // QuoteOrder has new order lines
        }
      }

      System.debug('oldQ is: Stage__c = ' + oldQ.Stage__c);
      System.debug('newQ is: Stage__c = ' + newQ.Stage__c);
      System.debug('newQ is: QTT_QuoteJobCountry__c = ' + newQ.QTT_QuoteJobCountry__c + ' StageName__c = ' + newQ.StageName__c + ' Order_Lines__c = ' +  newQ.Order_Lines__c);

      cancelledOrders = new List<QTT_Order__c>();

      //LS-341; 1/21/16  efuscarino/forefront
      //Check if Order has been cancelled
      if(oldQ.Stage__c != 'Cancelled System Order' && newQ.Stage__c == 'Cancelled System Order'){

        cancelledOrders.add(newQ); // add order to cancelled list

      } else { // if order has not been cancelled

        System.debug('newQ.QuoteOrder_Created_Opportunity__c is: '+newQ.QuoteOrder_Created_Opportunity__c);
        if (newQ.Opportunity__c != oldQ.Opportunity__c && ! newQ.QuoteOrder_Created_Opportunity__c ){ // if Opportunity link was changed but Opp was not created by this QuoteOrder

          ordersForFirstTimeLink.add(newQ); // add order to list for first time link
          System.debug(newQ.Id+' added to ordersForFirstTimeLink here');

        } else { // if Opportunity link was not changed

          ordersForOppSync.add(newQ); // add order to list for Opportunity sync
        }

        if ((newQ.QTT_QuoteJobCountry__c == 'USA' || newQ.QTT_QuoteJobCountry__c == 'CANADA')){ // create ServiceMax data only for orders in USA & Canada

          System.debug('oldQ.QTT_Order_Status__c is: ' + oldQ.QTT_Order_Status__c);
          System.debug('newQ.QTT_Order_Status__c is: ' + newQ.QTT_Order_Status__c);
          System.debug('newQ.Order_Lines__c is:' + newQ.Order_Lines__c);
          System.debug('hasNewOrderLines is: '+hasNewOrderLines);

          Boolean needsRelease0 = false;
          Boolean needsRelease1 = false;
          if (String.isBlank(oldQ.QTT_Order_Status__c) && String.isNotBlank(newQ.QTT_Order_Status__c) && newQ.Order_Lines__c > 0){ // if prior OrderStatus was blank and new Order Status is not blank and Order Lines exist
            needsRelease0 = true;
            System.debug('needsRelease0 is true here');
          }

          if (newQ.QTT_Order_Status__c == 'HFR' && hasNewOrderLines){ // if HFR and has new order lines
            needsRelease0 = true;
            System.debug('needsRelease0 is true here');
          }

          // if now Partial or Released and was not before AND Order Lines exist
          if ((newQ.QTT_Order_Status__c == 'Partial' || newQ.QTT_Order_Status__c == 'Released') && (oldQ.QTT_Order_Status__c != 'Partial' && oldQ.QTT_Order_Status__c != 'Released') && newQ.Order_Lines__c > 0){
            needsRelease1 = true;
            System.debug('needsRelease1 is true here');
          }

          if ((newQ.QTT_Order_Status__c == 'Partial' || newQ.QTT_Order_Status__c == 'Released') && hasNewOrderLines){ // if Partial or Released and new order Lines were added
            needsRelease1 = true;
            System.debug('needsRelease1 is true here');

            if (String.isBlank(newQ.Master_Work_Order__c)){
              needsRelease0 = true;
              System.debug('needsRelease0 is true here');
            }
          }
          System.debug('needsRelease0 is: '+needsRelease0+'; needsRelease1 is: '+needsRelease1);

          if (needsRelease0){
            //releaseZeroOrders.add(newQ); // add the QuoteOrder to the list of orders needing release0 data
            releaseZeroOrderIds.add(newQ.Id);
          }

          if (needsRelease1){
            releaseOneOrderIds.add(newQ.Id); // add the QuoteOrder to the list of orders possibly needing release1 data
          }

          if (! needsRelease0 && ! needsRelease1 && String.isNotBlank(newQ.Master_Work_Order__c)){

            syncMWOOrderIds.add(newQ.Id);
          }
        }        
      }
    }

    System.debug('cancelledOrders.size() is: '+cancelledOrders.size());
    System.debug('ordersForOppSync.size() is: '+ordersForOppSync.size());
    //LS-341; 1/21/16 efuscarino/forefront
    if(cancelledOrders.size() > 0){

        cancelOrder(cancelledOrders);
    }

    System.debug('ordersForOppSync are: '+ordersForOppSync);
    System.debug('ordersForFirstTimeLink are: '+ordersForFirstTimeLink);  
    Boolean firstTimeLink;
    if (! ordersForOppSync.isEmpty()){ // if there are Opportunities to sync

      firstTimeLink = false;
      syncRelatedOpps(ordersForOppSync,firstTimeLink); // sync Opp fields from QuoteOrder fields
    }

    if (! ordersForFirstTimeLink.isEmpty()){ // if there are Opportunities to link

      firstTimeLink = true;
      syncRelatedOpps(ordersForFirstTimeLink,firstTimeLink); // link QuoteOrder to Opportunity
    }

    List<String> orderActionList = new List<String>();
    String orderAction;

    for (String orderID : releaseZeroOrderIds){

      orderAction = orderID+'~'+'Release0';
      orderActionList.add(orderAction);
    }

    for (String orderID : releaseOneOrderIds){

      orderAction = orderID+'~'+'Release1';
      orderActionList.add(orderAction);
    }

    for (String orderID : syncMWOOrderIds){

      orderAction = orderID+'~'+'syncMWO';
      orderActionList.add(orderAction);
    }

    System.debug('orderActionList is: '+orderActionList);
    if (! orderActionList.isEmpty() && !donotRunCreateSVMXDataMethod){

      createServiceMaxData(orderActionList);
    }
  }

  @future
  public static void createServiceMaxData(List<String> orderActionList){
    
    donotRunCreateSVMXDataMethod = true;
    Map<String,List<String>> orderMap = getOrderMap(orderActionList); // map that will have the action indicator and list of order ids
    System.debug('orderMap is: '+orderMap);

    List<String> relZeroList = orderMap.get('Release0');
    Set<String> releaseZeroOrderIds = new Set<String>();
    if (relZeroList != null){
      releaseZeroOrderIds.addAll(relZeroList);
    }

    List<QTT_Order__c> releaseZeroOrders = new List<QTT_Order__c>();

    if (releaseZeroOrderIds != null){

      if (! releaseZeroOrderIds.isEmpty()){

        String objName = 'QTT_Order__c';
        String selectOrders  = 'SELECT ';
        selectOrders += buildQueryStringForObject(objName);
        List<String> valueList = new List<String>(releaseZeroOrderIds);
        
        selectOrders += ' FROM '+objName+' WHERE Id IN (\''+String.join(valueList,'\',\'')+'\')';
        System.debug('selectOrders is: '+selectOrders);
        if (selectOrders != null){

          releaseZeroOrders = Database.query(selectOrders); // get the QuoteOrders that need Release0 processing 
        }
      }
    }
    
    if (! releaseZeroOrders.isEmpty()){

      createReleaseZeroData(releaseZeroOrders); 
    }    

    List<String> relOneList = orderMap.get('Release1');
    Set<String> releaseOneOrderIds = new Set<String>();
    if (relOneList != null){
      releaseOneOrderIds.addAll(relOneList);
    }

    // process Release1 orders
    if (releaseOneOrderIds != null){

      if (! releaseOneOrderIds.isEmpty()){

        String release = 'Release1';

        // apply business rules to Master Work Orders where applicable
        createUpdateMasterWorkOrders(releaseOneOrderIds, release);

        // create Release1 Work Orders
        createReleaseWorkOrders(releaseOneOrderIds, release);
      }
    }    

    List<String> syncMWOList = orderMap.get('syncMWO');
    Set<String> syncMWOOrderIds = new Set<String>();
    if (syncMWOList != null){
      syncMWOOrderIds.addAll(syncMWOList);
    }

    if (syncMWOOrderIds != null){

      if (! syncMWOOrderIds.isEmpty()){ // if MWOs need to be synched

        syncRelatedMWOs(syncMWOOrderIds); // sync data from QuoteOrders to related Master Work Orders
      }
    }
    

    // Sync Order Lines
    /*List<QTT_Order_Line__c> olinesToUpdate = [SELECT Id FROM QTT_Order_Line__c WHERE QTT_Order__c IN :qOrderIds];

    if (olinesToUpdate.size() > 0){

      // process an update on all related lines. update trigger on order lines will handle sync of required fields from quote order to related order lines
      update olinesToUpdate;
    }*/
  }

  private static Map<String,List<String>> getOrderMap(List<String> orderActionList){

    Map<String,List<String>> orderMap = new Map<String,List<String>>();
    List<String> release0IdList = new List<String>();
    List<String> release1IdList = new List<String>();
    List<String> syncMWOIdList = new List<String>();
    String orderID;
    String actionID;

    for (String ord : orderActionList){

      if (String.isNotBlank(ord)){

        List<String> orderSplit = ord.split('~'); 

        if (orderSplit.size() == 2){

          orderID = orderSplit[0];
          actionID = orderSplit[1];

          if (actionID == 'Release0'){
            release0IdList.add(orderID);
          } else if (actionID == 'Release1'){
            release1IdList.add(orderID);
          } else if (actionID == 'syncMWO'){
            syncMWOIdList.add(orderID);
          }
        }
      }
    }

    if (! release0IdList.isEmpty()){
      orderMap.put('Release0', release0IdList);
    }

    if (! release1IdList.isEmpty()){
      orderMap.put('Release1', release1IdList);
    }

    if (! syncMWOIdList.isEmpty()){
      orderMap.put('syncMWO', syncMWOIdList);
    }

    return orderMap;

  } 

  public static String buildQueryStringForObject(String s){
  // Get a map of field name and field token
  String selects ='';
  String objType ='';

  List<string> selectFields = new List<string>();

  Map<String,Schema.SObjectType> targetType = Schema.getGlobalDescribe();

  if(targetType.containsKey(s)){

      objType = targetType.get(s).getDescribe().getName();   
  }
       
  for (Schema.SObjectField ft : targetType.get(objType).getDescribe().fields.getMap().values()){ // loop through all field tokens (ft)

      Schema.DescribeFieldResult fd = ft.getDescribe(); // describe each field (fd)                 

      selectFields.add(fd.getName());            
  }

  //verify that the selectFields list is not empty
  if (!selectFields.isEmpty()){

      selects = String.join(selectFields,',');
  }

  return selects;

}//End buildQueryStringForObject()
  
  //LS-341; 1/21/16 efuscarino/forefront
  public static void cancelOrder(List<QTT_Order__c> cancelledOrders){

    Set<Id> mwoSet = new Set<Id>();
    //Set<String> qttOrderNames = new Set<String>();
    Set<Id> qttOrderIdSet = new Set<Id>();

    Set<ID> oppIDs = new Set<ID>(); // define collection of Opportunity ids


    for(QTT_Order__c o : cancelledOrders){
      
      //o.QTT_Order_Status__c = '';
      
      //add to set of MWO
      mwoSet.add(o.Master_Work_Order__c);
      
      //add to string set of QTT ORder Name to Find Customer PO, QTT Release and QTT Order Lines to delete
      //qttOrderNames.add(o.Name);

      qttOrderIdSet.add(o.Id);

      oppIDs.add(o.Opportunity__c); // add opportunity id to the collection (LS-341 New Requirements 2/8/16)
    }

    //update(cancelledOrders);

    //Query for MWO
    //Update MWO Name with prefix of CANCELonMMDDYY
    List<Master_Work_Order__c> mwoList = [SELECT Id, Name, Cancelled__c FROM Master_Work_Order__c WHERE Id IN : mwoSet];
    if(mwoList.size() > 0){

      Date dToday = Date.today();
      DateTime dt = DateTime.newInstance(dToday.year(), dToday.month(),dToday.day());
      String dateStr = dt.format('MMDDYY');

      for(Master_Work_Order__c mwo : mwoList){

        mwo.Name = 'CANCELon'+dateStr+'_'+mwo.Name;
        mwo.Cancelled__c = true;

      }

      update mwoList;
    }

    //Query for QTT Release - or delete WHERE
    delete [SELECT Id FROM QTT_Release__c WHERE Quote_Order__c =: qttOrderIdSet];

    //Query for Customer PO - or delete WHERE
    delete [SELECT Id FROM QTT_PO__c WHERE QTT_Order__c =: qttOrderIdSet];
    
    //Query for QTT Order Lines - or delete WHERE
    delete [SELECT Id FROM QTT_Order_Line__c WHERE QTT_Order__c =: qttOrderIdSet];

    // (LS-341 New Requirements 2/8/16)
    if (! oppIDs.isEmpty()){

      resetOpportunityValuesForCancelledOrders(oppIDs); 
    }// END (LS-341 New Requirements 2/8/16)
  }//end cancelOrder()


  public static void createReleaseZeroData(List<QTT_Order__c> qOrders){
    // check if ServiceMax is disabled
    Boolean getOut = checkServiceMaxDisabled();
    if (getOut){
      return;
    }

    List<Job__c> existingJobs = new List<Job__c>(); // define list of existing Jobs
    Map<String,Job__c> existingJobsMap = new Map<String,Job__c>(); // define map of Jobs keyed by name
    Map<String,Job__c> jobsToUpsertMap = new Map<String,Job__c>(); // define map of Jobs to insert/update
    Set<String> releaseZeroOrderIds = new Set<String>(); // define collection of ids for QuoteOrders that are at Release0
    Set<String> releaseZeroForLocationOrderIds = new Set<String>(); // define collection of ids for QuoteOrders that are at Release0 and need Locations created
    List<QTT_Order__c> releaseZeroOrders = new List<QTT_Order__c>(qOrders); // define list of QuoteOrders that are at Release0
    List<QTT_Order__c> releaseZeroForInstalledProductOrders = new List<QTT_Order__c>(); // define list of QuoteOrders that are at Release0 and need Installed Products created
    List<Master_Work_Order__c> releaseZeroMasterWorkOrders = new List<Master_Work_Order__c>(); // define list of MasterWorkOrders that are created from the QuoteOrders
    Set<ID> qOIDsForContracts = new Set<ID>(); // define collection of ids for QuoteOrders that need contracts auto-generated
    String release = 'Release0';
    Set<String> jNumbers = new Set<String>(); // define collection of Job Numbers

    for (QTT_Order__c qOrd : qOrders){ // iterate thru QuoteOrders

      releaseZeroOrderIds.add(qOrd.id); // add the QuoteOrder id to the collection

      if (String.isNotBlank(qOrd.QTT_Job_Number__c)){ // QuoteOrder has a Job#

        jNumbers.add(qOrd.QTT_Job_Number__c); // add the Job# to the collection
      }

      if (String.isNotBlank(qOrd.TSP_Part_Number__c) || String.isNotBlank(qOrd.Contract_Part_Number__c)){ // if the QuoteOrder has a TSP or Contract part number

        qOIDsForContracts.add(qOrd.Id); // add the QuoteOrder id to the collection
      }

      if (String.isBlank(qOrd.Master_Work_Order__c)){ // if the QuoteOrder does not already have a MWO

        releaseZeroForLocationOrderIds.add(qOrd.Id); // add the id to the collection for new Locations
        releaseZeroForInstalledProductOrders.add(qOrd); // add the order to the list for new Installed Products
      }
    }

    // if collection has Job Numbers, get list of existing Jobs and build map of Jobs keyed by Job Number
    if (jNumbers.size() > 0){

      existingJobs = [select Id, Name from Job__c where Name in :jNumbers];

      if (existingJobs.size() > 0){

        for (Job__c job : existingJobs){ // process jobs and build map by job number

          existingJobsMap.put(job.name, job); // add job to the map
        }
      }
    }

    // process Quote Orders and create/update jobs as needed
    for(QTT_Order__c qOrd : qOrders){

      Job__c job = existingJobsMap.get(qOrd.QTT_Job_Number__c); // check if the Job already exists

      if (job == null){ // if Job doesn't already exist

        jobsToUpsertMap.put(qOrd.QTT_Job_Number__c, createJob(qOrd)); //add job to the upsert map 

      } else { // if Job exists

        job.Integrated_System_Notes__c = qOrd.QTT_IFS_Notes__c; // update IFS Notes on the Job
        jobsToUpsertMap.put(job.Name, job); //add job to the upsert map 
      }
    }

    if (jobsToUpsertMap.size() > 0){ // if there are new jobs to insert in the database

      upsert jobsToUpsertMap.values(); // insert jobs into the database
    }

    if (! releaseZeroForLocationOrderIds.isEmpty()){ // if ids were collected for new Locations

      createReleaseZeroLocations(releaseZeroForLocationOrderIds);
    }

    if (! releaseZeroForInstalledProductOrders.isEmpty()){ // if orders need new Inatalled Products created

      createReleaseZeroInstalledProducts(releaseZeroForInstalledProductOrders);
    }

    if (releaseZeroOrderIds.size() > 0){

      // create Master Work Orders
      createUpdateMasterWorkOrders(releaseZeroOrderIds, release);

      //  Create Work Orders
      createReleaseWorkOrders(releaseZeroOrderIds, release);
    }

    if (! qOIDsForContracts.isEmpty()){ // if there are QuoteOrders that need contracts

      autoGenContracts(qOIDsForContracts); // call method to generate contracts
    }
  }

  private static void createUpdateMasterWorkOrders(Set<String> qOrderIds, String release){

    if (qOrderIds.size() > 0){

      Set<String> qttExternalIDs = new Set<String>(); // define collection of Job.Quote values

      // get releaseZero QuoteOrders
      List<QTT_Order__c> releaseOrders = [SELECT Id, Job_Number__c, QTT_Job_Number__c, QTT_Quote_RID__c, QTT_Order_RID__c, QTT_Ordered_Rev__c,
                Ordered_Revision__c, QTT_QuoteJobCity__c, QTT_QuoteJobCountry__c, QTT_QuoteJobCounty__c, PrimarySystemName__c,
                QTT_QuoteJobState__c, Primary_System__c, Blanket_Value__c, Target_Startup__c, QTT_External_ID__c,
                Target_Completion__c, Target_Release__c, Target_PreWire__c, QTT_Quote_Order_Name__c, Estimated_SPV_Doc_Hours__c,
                Estimated_Elective_Service_Hours__c, Estimated_Training_Hours__c, Estimated_Startup_Hours__c, Estimated_Prewire_Hours__c
                FROM QTT_Order__c WHERE Id IN :qOrderIds];

      for (QTT_Order__c qOrd : releaseOrders){ // process QuoteOrders to collect Job.Quote values

        if (String.isNotBlank(qOrd.QTT_External_ID__c)){ // if QuoteOrder has an external ID

          qttExternalIDs.add(qOrd.QTT_External_ID__c); // add the external id (Job.Quote) to the collection
        }
      }

      // get Business Rules
      List<Business_Rules__c> busRules = [select Id, of_Days_from_HFR_Integration_Consult__c, of_Days_from_HFR_Pre_Construction__c, Blanket_Value__c
                    , Job_Location_State__c, Release_0_Target_Prewire_Date__c, Release_1_to_Startup_Days__c, System_Type__c
                    , Value_Comparison__c from Business_Rules__c];

      if (releaseOrders.size() > 0){

        // get existing Master Work Orders related to QuoteOrders based on Job.Quote
        List<Master_Work_Order__c> masterWOList = new List<Master_Work_Order__c>([SELECT Id, Job__c, Name, Order__c, Ordered_Revision__c, Primary_System__c, State__c, City__c, Country__c
                                                                                  , Target_Completion__c, QTT_Target_Completion_Date__c, Target_Release__c, Target_PreWire__c, Target_Startup__c
                                                                                  , QTT_Target_Startup_Date__c, Blanket_Value__c, Target_PreConstruction__c, Target_Integration_Consultation__c, Location__c
                                                                                  FROM Master_Work_Order__c WHERE Name IN :qttExternalIDs]);

        Map<String,Master_Work_Order__c> mwoNameMap = new Map<String,Master_Work_Order__c>(); // define map of Master Work Orders by Name (Job.Quote)

        if (masterWOList.size() > 0){ // if related Master Work Orders exist

          for (Master_Work_Order__c mWO : masterWOList){ // for each Master Work Order

            mwoNameMap.put(mWO.Name, mWO); // add the MWO to the map
          }
        }

        Master_Work_Order__c mWO; // define Master Work Order variable used to update existing or create new Master Work Order

        List<Master_Work_Order__c> mWOsToUpsert = new List<Master_Work_Order__c>();
        Set<Id> qOIDsForOrderLineUpdate = new Set<Id>();

        Map<String,SVMXC__Site__c> locationNameMap = getLocationsFromQuoteOrders(releaseOrders); // get existing locations with matching name based on Lutron's naming standard for auto-created locations
        Map<String,SVMXC__Installed_Product__c> iProdNameMap = getInstalledProductsFromQuoteOrders(releaseOrders); // get existing Installed Products with matching name based on Lutron's naming standard

        for (QTT_Order__c qOrd : releaseOrders){ // for each QuoteOrder

          if (mwoNameMap.keySet().contains(qOrd.QTT_External_ID__c)){ // if a Master Work Order already exists for the same Job.Quote

            mWO = mwoNameMap.get(qOrd.QTT_External_ID__c); // get the Master Work Order from the map

          } else { // if a Master Work Order does not exist for the same Job.Quote

            mWO = new Master_Work_Order__c(Job__c = qOrd.Job_Number__c); // create a new Master Work Order and set the Master-Detail relationship to Job
            qOIDsForOrderLineUpdate.add(qOrd.Id);
          }

          setMWOValuesFromQuoteOrder(qOrd,mWO); // set Master Work Order fields from QuoteOrder field values

          if (String.isBlank(mWO.Location__c)){ // if MWO doesn't already have a location

            if (locationNameMap.size() > 0){ // if locations with matching names exist

              /* if map has locations by name, attempt to lookup
               * the location for this MasterWorkOrder */
              String locName = setStandardLocationName(qOrd.QTT_Quote_Order_Name__c,qOrd.QTT_QuoteJobCity__c,qOrd.QTT_QuoteJobState__c); //derive the standard location name

              if (String.isNotBlank(locName) && locationNameMap.get(locName.toUpperCase()).Id != null){

                mWO.Location__c = locationNameMap.get(locName.toUpperCase()).Id; // attempt to set the location id on the Master Work Order by looking up in location map by name
              }
            }
          }

          // BEGIN: 2/25/2016; J.Aquino/ForeFront; LS-396 
          // Populate the new Installed Product lookup on the MWO
          System.debug('mWO.Installed_Product__c is: '+mWO.Installed_Product__c+' & iProdNameMap is: '+iProdNameMap);
          if (String.isBlank(mWO.Installed_Product__c) && iProdNameMap.size() > 0){ // if MWO doesn't already have an Installed Product and Installed Products with matching names exists

            String iProdName = qOrd.QTT_External_ID__c+'_'+qOrd.PrimarySystemName__c; // set the name to lookup based on Lutron's naming convention

            SVMXC__Installed_Product__c iProd = iProdNameMap.get(iProdName); // get the installed product from the map
            System.debug('iProd is: '+iProd);
            if (iProd != null){

              mWO.Installed_Product__c = iProd.Id; // set the Installed product lookup
              System.debug('mWO.Installed_Product__c is: '+mWO.Installed_Product__c+' & iProdName is: '+iProdName);              
            }
            
          }
          // END: 2/25/2016; J.Aquino/ForeFront; LS-396

          mWOsToUpsert.add(mWO); // add the new or existing Master Work Order to the list
        }

        if (mWOsToUpsert.size() > 0 ){ // if there are Master Work Orders to be created or updated

          for (Master_Work_Order__c masterWO : mWOsToUpsert){ // for each Master Work Order

            applyBusinessRules(masterWO, release, busRules); // attempt to apply business rules
          }

          upsert mWOsToUpsert; // update or create Master Work Orders
        }

        if (! qOIDsForOrderLineUpdate.isEmpty()){

          List<QTT_Order_Line__c> olinesToUpdate = [SELECT Id FROM QTT_Order_Line__c WHERE QTT_Order__c IN :qOIDsForOrderLineUpdate];

          if (olinesToUpdate.size() > 0){

            // process an update on all related lines. update trigger on order lines will handle sync of required fields from quote order to related order lines
            update olinesToUpdate;
          }
        }
      }
    }
  }

  private static Job__c createJob(QTT_Order__c qOrd){
    Job__c job = new Job__c(); // new Job object
    job.OwnerId = qOrd.OwnerId;
    job.Name = qOrd.QTT_Job_Number__c;
    job.Job_Name__c = qOrd.Job_Name__c;
    job.Integrated_System_Notes__c = qOrd.QTT_IFS_Notes__c;
    return job;
  }

  private static void createOppsForQuoteOrders(List<QTT_Order__c> qOrderList){

    // check if Opportunity Processing is disabled
    Boolean getOut = checkOpportunitiesDisabled();
    if (getOut){
      return;
    }

    // define variable used to determine if Opportunity needs to be synched
    Boolean oppNeedsSync = false;

    // define list of new Opportunities to be created
    List<Opportunity> newOppsToCreate = new List<Opportunity>();

    // build map of all Opportunity record types
    Schema.SObjectType oppType = Opportunity.sObjectType;
    Schema.DescribeSObjectResult resSchema = oppType.getDescribe();
    Map<String,Schema.RecordTypeInfo> oppRecordTypeInfo = resSchema.getRecordTypeInfosByName();

    // process QuoteOrders and create new Opportunities as needed
    for (QTT_Order__c qOrd : qOrderList){

      // if QuoteOrder has a QTT_Opp_RID but no Opportunity id, create a new Opp for the QuoteOrder
      if (String.isNotBlank(qOrd.QTT_Opportunity_RID__c) && String.isBlank(qOrd.Opportunity__c)){

        Opportunity oppToCreate = new Opportunity();

        // get record type id using the record type name sent by QTT
        Schema.RecordTypeInfo opportunityRT = oppRecordTypeInfo.get(qOrd.QTT_OpportunityRecordType__c);

        if (opportunityRT != null){

          // if the record type was found, set the id
          oppToCreate.RecordTypeId = opportunityRT.getRecordTypeId();

        } else {

          // if the record type was not found, use the default record type to set the id
          opportunityRT = oppRecordTypeInfo.get('Commercial Systems');
          oppToCreate.RecordTypeId = opportunityRT.getRecordTypeId();
        }

        // Sync data from Quote Order to Opportunity
        Boolean firstTimeLink = true;
        oppNeedsSync = syncOppFromQuoteOrder(qOrd,oppToCreate,firstTimeLink);
        System.debug('oppNeedsSync: '+oppNeedsSync);
        System.debug('qOrd: '+qOrd);
        System.debug('oppToCreate: '+oppToCreate);

        if (oppNeedsSync){

          newOppsToCreate.add(oppToCreate); // add to the list of Opps to be created
        }
      }
    }

    // if new Opportunities were created, save themn to the database
    if (newOppsToCreate.size() > 0){
      System.debug('newOppsToCreate: '+newOppsToCreate);
      Database.SaveResult[] oppSR = Database.insert(newOppsToCreate, false);

      Integer i = 0;

      for (Database.SaveResult sr : oppSR){

        if (! sr.isSuccess()){

          System.debug('Opportunity was not created for QuoteOrder '+newOppsToCreate[i].QTT_Project_Number__c+'.'+newOppsToCreate[i].QTT_Quote_Number__c+' due to error: '+sr.getErrors()[0]);
        }

        i++;
      }

      /* Now we need to update QuoteOrders with the Opportunity Id
       * of the new Opportunities just created for them
       */

      // define map of Opportunities keyed by QTT_RID
      Map<String,Opportunity> newOppMap = new Map<String,Opportunity>();

      // process new Opps and add to map
      for (Opportunity newOpp : newOppsToCreate){

        // if Opp was sucessfully created, add it to the map
        if (String.isNotBlank(newOpp.Id)){

          newOppMap.put(newOpp.QTT_RID__c, newOpp);
        }
      }

      // get the corresponding Opp from the map and get the OppId to update the lookup from QuoteOrder to Opportunity
      for (QTT_Order__c qOrd : qOrderList){

        // if Quote Order is not linked to an Opportunity attempt to find the correct Opportunity to link it to
        if (String.isBlank(qOrd.Opportunity__c)){

          Opportunity newOpp = newOppMap.get(qOrd.QTT_Opportunity_RID__c);

          if (newOpp != null){

            qOrd.Opportunity__c = newOpp.Id;
          }
        }
      }
    }
  }

  private static void unlinkOppsFromQuoteOrders(List<QTT_Order__c> qOrderList){

     // check if Opportunity Processing is disabled
    Boolean getOut = checkOpportunitiesDisabled();
    if (getOut){
      return;
    }

    //System.debug('qOrderList is: '+qOrderList);
    Map<ID,Opportunity> oppMap = getOppsRelatedToQuoteOrders(qOrderList); // get map of opportunities related to the QuoteOrders
    System.debug('oppMap is: '+oppMap);
    for(Id i : oppMap.keySet()){
      //System.debug(oppMap.get(i).Opportunity_Link_History__r);
    }
    Set<Id> oppIDs = oppMap.keySet();
    //System.debug('oppIDs are: '+oppIDs); 

    unlinkRevisionsFromOpportunities(oppIDs); // remove the Revisions from the Opportunities that are being unlinked

    List<Opportunity> oppsToUpdateList = new List<Opportunity>(); // define list of Opps to be updated

    for (QTT_Order__c qOrd : qOrderList){ // iterate thru all QuoteOrders 
      //System.debug('qOrd.Opportunity__c is: '+qOrd.Opportunity__c+'; and qOrd.Unlink_QTT_Opportunity_c__c is:'+qOrd.Unlink_QTT_Opportunity_c__c);
      if (String.isNotBlank(qOrd.Opportunity__c)){ // if QuoteOrder has an Opportunity

        Opportunity oppToUpdate = oppMap.get(qOrd.Opportunity__c); // get the Opportunity from the map
        //System.debug('oppToUpdate is: '+oppToUpdate);
        if (oppToUpdate != null){ // if Opportunity was found in the map

          // reset values in Opportunity fields when unlinking
          oppToUpdate.QTT_Project_Number__c = null;
          oppToUpdate.QTT_Quote_Number__c = null;
          oppToUpdate.QTT_Quote_Name__c = null;
          oppToUpdate.Lutron_Rep__c = null;
          oppToUpdate.QTT_Project_Name__c = null;
          oppToUpdate.QTT_Project__c = null; // 3/1/2016 new requirement to set Parent Opportunity to null when unlinking
          //oppToUpdate.Primary_System__c = null;
          //oppToUpdate.QTT_Project_Manager__c = null;
          //oppToUpdate.Job__c = null;
          //oppToUpdate.Job_Number__c = null;
          //oppToUpdate.Order_Status__c = null;
          //oppToUpdate.QTT_Target_Completion_Date__c = null;
          //oppToUpdate.QTT_Target_Release_Date__c = null;
          //oppToUpdate.QTT_Target_Submittal_Date__c = null;
          //oppToUpdate.QTT_Target_PreWire_Date__c = null;
          //oppToUpdate.QTT_Target_StartUp_Date__c = null;
          // oppToUpdate.QTT_Order_Status__c = null;
          //oppToUpdate.Installation_Type__c = null;
          //oppToUpdate.Bid_Date__c = null;
          //oppToUpdate.Vertical_Market__c = null;
          //oppToUpdate.Construction_Type__c = null;
          //oppToUpdate.QTT_PM_Job_Status__c = null;
          //oppToUpdate.Updated_From_First_Revision__c = false;

          if (! oppToUpdate.Opportunity_Link_History__r.isEmpty()){ // if the Opportunity Link History was found

            for (Opportunity_Link_History__c oLH : oppToUpdate.Opportunity_Link_History__r){

              // set the Opportunity field values back to what they were at the time this QuoteOrder was linked to the Opportunity
              if (oLH.Amount__c == 0 || oLH.Amount__c == null){ // if previous amount was 0 or null

                oppToUpdate.Amount = oLH.Amount__c; // set Opportunity amount to previous amount
                oppToUpdate.CurrencyIsoCode = oLH.CurrencyIsoCode; // set Opportunity currency to previous currency
              }
              oppToUpdate.StageName = oLH.Stage__c;
              oppToUpdate.Installation_Type__c = oLH.Installation_Type__c;
              oppToUpdate.Bid_Date__c = oLH.Bid_Date__c;
              oppToUpdate.Vertical_Market__c = oLH.Vertical_Market__c;
              oppToUpdate.Construction_Type__c = oLH.Construction_Type__c;
            }
          }

          oppsToUpdateList.add(oppToUpdate); // add the Opp to the list to be updated
        }

        if (qOrd.Unlink_QTT_Opportunity_c__c){ // if this QuoteOrder received an unlink request

          // unlink the Opp from the QuoteOrder
          qOrd.Opportunity__c = null;
          qOrd.QTT_Opportunity_RID__c = null;
          qOrd.Account__c = null;
        }
      } 

      // if Opps were updated/unlinked, save them to the database
      if (oppsToUpdateList.size() > 0){

        Database.SaveResult[] oppSR = Database.update(oppsToUpdateList, false);

        Integer i = 0;

        for (Database.SaveResult sr : oppSR){

          if (! sr.isSuccess()){

            System.debug('Opportunity was not updated for QuoteOrder '+oppsToUpdateList[i].QTT_Project_Number__c+'.'+oppsToUpdateList[i].QTT_Quote_Number__c+' due to error: '+sr.getErrors()[0]);
          } else {
            System.debug('Opportunity was updated as: '+oppsToUpdateList[i]);
          }

          i++;
        }
      }
    }
  }

  private static Map<ID,Opportunity> getOppsRelatedToQuoteOrders(List<QTT_Order__c> qOrderList){

    // initialize map that will store related Opportunities that need to be synched
    Map<Id,Opportunity> oppMap = new Map<Id,Opportunity>();

    Set<Id> oppIds = new Set<Id>(); // defne collection of Opportunity ids
    Set<String> qOrdExternalIDs = new Set<String>(); // define collection QuoteOrder External ids

    for (QTT_Order__c qOrd : qOrderList){ // iterate thru QuoteOrders

      if (String.isNotBlank(qOrd.Opportunity__c)){ // if this QuoteOrdfer has an Opportunity

        oppIds.add(qOrd.Opportunity__c); // add the Opportunity id to the collection
      }

      if (String.isNotBlank(qOrd.QTT_External_ID__c)){

        qOrdExternalIDs.add(qOrd.QTT_External_ID__c); // add the QuoteOrder External id to the collection
      }
    }

    // if related Opportunities found, build map of Opportunities used to lookup the Opportunity Ids
      if (oppIds.size() > 0){

      // build map of related Opportunities and Opportunity Link History from prior
      oppMap = new Map<Id,Opportunity>([SELECT Id, Job_Number__c, Job__c, QTT_Project_Number__c, Name, Amount, QTT_Project_Manager__c
                                          , State__c, City__c, Country__c, QTT_Quote_Name__c, QTT_Order_Status__c, QTT_System_Type__c
                                          , QTT_Target_Completion_Date__c, QTT_Target_Release_Date__c, QTT_Target_PreWire_Date__c
                                          , QTT_Target_StartUp_Date__c, StageName, Primary_System__c, AccountId, QTT_Quote_Number__c
                                          , QTT_RID__c, Forecast_Lutron__c, CloseDate, QTT_Integration_Status__c, QTT_PM_Job_Status__c
                                          , Bid_Date__c, Installation_Type__c, Vertical_Market__c, Construction_Type__c, Lutron_Rep__c
                                          , Share_with_Lutron_Rep__c, QTT_Project_Name__c, CurrencyIsoCode,
                                          (SELECT Id, Amount__c, Bid_Date__c, Construction_Type__c, CurrencyIsoCode, Installation_Type__c, 
                                                  Opportunity_QTT_RID__c, Opportunity__c, Quote_Order_QTT_Ext_ID__c, Quote_Order__c,Stage__c,Vertical_Market__c 
                                            FROM Opportunity_Link_History__r WHERE Quote_Order_QTT_Ext_ID__c IN :qOrdExternalIDs ORDER BY CreatedDate DESC LIMIT 1)
                                        FROM Opportunity WHERE Id IN :oppIds]);
    }

    return oppMap;
  }

  private static void syncRelatedOpps(List<QTT_Order__c> qOrdersToSync, Boolean firstTimeLink){

    // check if Opportunity Processing is disabled
    Boolean getOut = checkOpportunitiesDisabled();
    if (getOut){
      return;
    }

    // define variable used to determine if Opportunity needs to be synched
    Boolean oppNeedsSync = false;

    // get map of opportunities related to the Quote Orders
    Map<ID,Opportunity> oppMap = getOppsRelatedToQuoteOrders(qOrdersToSync);

    // define list of Opps to update
    List<Opportunity> oppsToUpdateList = new List<Opportunity>();

    // loop thru all new/updated QuoteOrders sync related Opps
    for (QTT_Order__c qOrd : qOrdersToSync){

      // if QuoteOrder is not Cancelled and has an OppId get the Opp from the map
      if (qOrd.Stage__c != 'Cancelled System Order' && String.isNotBlank(qOrd.Opportunity__c)){

        // get the Opp from the map
        Opportunity oppToUpdate = oppMap.get(qOrd.Opportunity__c);

        // sync the Opp fields from the QuoteOrder field values if needed
        System.debug('firstTimeLink is: '+firstTimeLink);
        oppNeedsSync = syncOppFromQuoteOrder(qOrd,oppToUpdate,firstTimeLink);
        System.debug('oppNeedsSync: '+oppNeedsSync);
        System.debug('qOrd: '+qOrd);
        System.debug('oppToUpdate: '+oppToUpdate);

        if (oppNeedsSync){

          oppsToUpdateList.add(oppToUpdate); // add to the list of Opps to be updated
        }
      }
    }

    // if Opps to be updated exist, save them to the database
    if (oppsToUpdateList.size() > 0){

      Database.SaveResult[] oppSR = Database.update(oppsToUpdateList, false);

      Integer i = 0;

      for (Database.SaveResult sr : oppSR){

        if (! sr.isSuccess()){

          System.debug('Opportunity was not updated for QuoteOrder '+oppsToUpdateList[i].QTT_Project_Number__c+'.'+oppsToUpdateList[i].QTT_Quote_Number__c+' due to error: '+sr.getErrors()[0]);
        } else {
          System.debug('Opportunity was updated as: '+oppsToUpdateList[i]);
        }  

        i++;
      }
    }
  }

  private static void setJobNumber(List<QTT_Order__c> qOrders, Set<String> jNumbers){

    // define list of jobs related to quote orders
    List<Job__c> jobs = new List<Job__c>();

    // define map of Jobs by Job Number
    Map<String, Job__c> jobMap = new Map<String, Job__c>();

    // if collection has Job Numbers, build map of Jobs keyed by Job#
    if (jNumbers.size() > 0){

      jobs = [SELECT Id, Name FROM Job__c WHERE Name IN :jNumbers];

      // if related Jobs were found, process list of jobs and build map keyed by Job Number
      if (jobs.size() > 0){

        for (Job__c myJob : jobs){

          jobMap.put(myJob.name, myJob);
        }

        // process quote orders and get related Job id from map
        for (QTT_Order__c qOrd : qOrders){

          Job__c job = jobMap.get(qOrd.QTT_Job_Number__c);

          if (job != null){

            qOrd.Job_Number__c = job.id;

          } else {

            qOrd.Job_Number__c = null;
          }
        }
      }
    }
  }

  private static void orderedRevSetter(Map<ID,QTT_Order__c> qOrdsForRevision){

    // define map of revisions by RevisionRID
    Map<String,QTT_Quote_Revision__c> revMap = new Map<String,QTT_Quote_Revision__c>();

    List<QTT_Quote_Revision__c> revisions = new List<QTT_Quote_Revision__c>();

    if(executionQTTIdList.retainAll(qOrdsForRevision.keySet()))
    {
      revisions.addAll(executionQTTQuoteRevisionMap.values());
    }
     else
    {
      revisions =  [SELECT Id, Quote_Order__c, QTT_Revision_RID__c, Revision_Number__c
                                                  FROM QTT_Quote_Revision__c WHERE Quote_Order__c IN :qOrdsForRevision.keySet()];
    }  
    

    // get revisions related to the QuoteOrders
   /* for (QTT_Quote_Revision__c revisions : revisionsList){

      // initialize collection of QuoteOrder ids to process for each batch
      Set<ID> qOIDs = new Set<ID>();

      /* iterate list of revisions looking for the revisions that are refereneced
       * by the QuteOrders as the "OrderedRevision" and update the lookup on
       * the related QuoteOrders */
       System.debug('revisions has: ' + revisions);

      Set<ID> qOIDs = new Set<ID>();
      for (QTT_Quote_Revision__c rev : revisions) {

        // add the revision to the map keyed by RevisionRID
        revMap.put(rev.QTT_Revision_RID__c, rev);

        // add the QuoteOrder id to the collection
        qOIDs.add(rev.Quote_Order__c);

      }

      if (qOIDs.size() > 0)
      {

        // process batch of QuoteOrders
        for (ID qOID : qOIDs)
        {

          // get the QuoteOrder
          QTT_Order__c qOrd = qOrdsForRevision.get(qOID);

          // if the QuoteOrder has an OrderedRevision from QTT, update the lookup on the QuoteOrder to point to the correct Revision
          if (qOrd != null)
          {
            if (String.isNotBlank(qOrd.QTT_Ordered_Rev__c))
            {

              // get the revision from the map based on the RevisionRID
              QTT_Quote_Revision__c rev = revMap.get(qOrd.QTT_Ordered_Rev__c);

              // if the Revision was found, update the lookup o hte QuoteOrder withe Revision's id
              if (rev != null)
              {

                qOrd.Ordered_Revision__c = rev.Id;
              }

            // if the QuoteOrder does not have an OrderedRevision from QTT, update the lookup on the QuoteOrder to null
            } else 
            {

              qOrd.Ordered_Revision__c = null;
            }
          }
        }
      }
    //}
  }

  private static void createReleaseWorkOrders(Set<String> qOrderIds, String rel){
    // check if ServiceMax is disabled
    Boolean getOut = checkServiceMaxDisabled();
    if (getOut){
      return;
    }

    //get all Work Order Record Types
      Schema.SObjectType s = SVMXC__Service_Order__c.sObjectType;
      Schema.DescribeSObjectResult resSchema = s.getDescribe();
      Map<String,Schema.RecordTypeInfo> workOrderRecordTypeInfo = resSchema.getRecordTypeInfosByName();

    List<SVMXC__Service_Order__c> releaseWorkOrders = new List<SVMXC__Service_Order__c>();

    Set<String> releaseActivities = new Set<String>();
    if (rel == 'Release0'){
      releaseActivities.add('All Work Orders for Release 0');
      releaseActivities.add('WOA 2');
      releaseActivities.add('WOA 3');
      releaseActivities.add('WOA 4');
      releaseActivities.add('WOA 5');
      releaseActivities.add('WOA 6');
    }

    if (rel == 'Release1'){
      releaseActivities.add('WOA 1');
      releaseActivities.add('WOA 2');
      releaseActivities.add('WOA 3');
      releaseActivities.add('WOA 4');
      releaseActivities.add('WOA 5');
      releaseActivities.add('WOA 6');
    }

    System.debug('getting OrderLines for release WO Activities. releaseActivites ='+releaseActivities+'; qOrderIds='+qOrderIds);
    List<QTT_Order_Line__c> oLinesForWO = [SELECT Id, Product__c, Product__r.Release_1_Breakpoint__c,
                        Product__r.WO_Activity_1__c, Product__r.WO_Activity_2__c, Product__r.WO_Activity_3__c,
                        Product__r.WO_Activity_4__c, Product__r.WO_Activity_5__c, Product__r.WO_Activity_6__c,
                        Job__c, Master_Work_Order__c, QTT_Order__r.Account__c, QTT_Order__r.Target_Release__c,
                        QTT_Order__r.Target_Startup__c, QTT_Order__r.Target_Completion__c,
                        QTT_Order__r.Target_PreWire__c, QTT_Order__r.Primary_System__c,
                        QTT_Order__r.Job_Number__c, QTT_Order__r.Master_Work_Order__c, QTT_Order__r.Master_Work_Order__r.Installed_Product__c,
                        (SELECT Id FROM Work_Orders__r)
                        FROM QTT_Order_Line__c WHERE QTT_Order__c IN :qOrderIds
                                                AND Product__r.Release_1_Breakpoint__c IN :releaseActivities
                                                AND Order_Line_Deleted__c = false
                                                AND Id NOT IN (SELECT QTT_Order_Line__c FROM SVMXC__Service_Order__c WHERE WO_AutoCreated_By__c = :rel)];

    if (oLinesForWO.size() > 0){
      Map<Integer,String> WO_Activities = new Map<Integer,String>();

      // Collect WO Activites on this Product for the requested Release
      for (QTT_Order_Line__c oLine : oLinesForWO){

        WO_Activities.clear();

        if (String.isNotBlank(oLine.Product__r.WO_Activity_1__c)){
          WO_Activities.put(1, oLine.Product__r.WO_Activity_1__c);
        }

        if (String.isNotBlank(oLine.Product__r.WO_Activity_2__c)){
          WO_Activities.put(2, oLine.Product__r.WO_Activity_2__c);
        }

        if (String.isNotBlank(oLine.Product__r.WO_Activity_3__c)){
          WO_Activities.put(3, oLine.Product__r.WO_Activity_3__c);
        }

        if (String.isNotBlank(oLine.Product__r.WO_Activity_4__c)){
          WO_Activities.put(4, oLine.Product__r.WO_Activity_4__c);
        }

        if (String.isNotBlank(oLine.Product__r.WO_Activity_5__c)){
          WO_Activities.put(5, oLine.Product__r.WO_Activity_5__c);
        }

        if (String.isNotBlank(oLine.Product__r.WO_Activity_6__c)){
          WO_Activities.put(6, oLine.Product__r.WO_Activity_6__c);
        }

        Integer bkPoint;
        String brkText = oLine.Product__r.Release_1_Breakpoint__c;

        if (brkText == 'All Work Orders for Release 0'){
          bkPoint = 99;
        } else if (brkText == 'WOA 1'){
          bkPoint = 1;
        } else if (brkText == 'WOA 2'){
          bkPoint = 2;
        } else if (brkText == 'WOA 3'){
          bkPoint = 3;
        } else if (brkText == 'WOA 4'){
          bkPoint = 4;
        } else if (brkText == 'WOA 5'){
          bkPoint = 5;
        } else if (brkText == 'WOA 6'){
          bkPoint = 6;
        }

        System.debug('WO_Activities(map)='+WO_Activities);
        System.debug('brkText='+brkText);
        System.debug('bkPoint='+bkPoint);

        // Get custom setting to cross ref WO Activities to Work Order Record Types & Purpose of Visist
        // If custom setting not found or record type is null or invalid, DO NOT CREATE THE WORK ORDER
          Map<String,WO_Activity_Xref__c> xrefWO_RT = WO_Activity_Xref__c.getall();

        // Iterate thru WO Activities for this Product and create required Work Orders
        for (Integer WOA : WO_Activities.keySet()){
          Boolean createWO = false;
          if (rel == 'Release0' && WOA < bkPoint){
            createWO = true;
          } else if (rel == 'Release1' && WOA >= bkPoint){
            createWO = true;
          }

          // if a WO Activity was found for the specific Release, create a Work Order
          if (createWO){
            SVMXC__Service_Order__c workOrder = new SVMXC__Service_Order__c();

            // Get Record Type & Purpose of Visit values from Custom Settings
            String rcdTypeName;
            Schema.RecordTypeInfo workOrd_RT;
            String workOrdActivity = WO_Activities.get(WOA);
            WO_Activity_Xref__c wOX = xrefWO_RT.get(workOrdActivity);
            if (wOX != null){
              rcdTypeName = wOX.WO_Record_Type_Name__c;
              workOrd_RT = workOrderRecordTypeInfo.get(rcdTypeName);
              if (workOrd_RT != null){
                workOrder.RecordTypeId = workOrd_RT.getRecordTypeId();
                workOrder.SVMXC__Purpose_of_Visit__c = wOX.Purpose_of_Visit__c;
                workOrder.SVMXC__Company__c = oLine.QTT_Order__r.Account__c;
                workOrder.Job_Number__c = oLine.QTT_Order__r.Job_Number__c;
                workOrder.Master_Work_Order__c = oLine.QTT_Order__r.Master_Work_Order__c;
                workOrder.SVMXC__Product__c = oLine.QTT_Order__r.Primary_System__c;
                workOrder.SVMXC__Component__c = oLine.QTT_Order__r.Master_Work_Order__r.Installed_Product__c;
                workOrder.QTT_Order_Line__c = oLine.Id;
                workOrder.Billable_Entitlement__c = 'Prepaid on BOM';
                workOrder.WO_AutoCreated_By__c = rel;

                releaseWorkOrders.add(workOrder);
                System.debug('WOA='+WOA);
                System.debug('workOrderRecordTypeInfo='+workOrderRecordTypeInfo);
                System.debug('rcdTypeName='+rcdTypeName);
                System.debug('record type id ='+workOrder.RecordTypeId);
              }
            }
          }
        }
      }

      if (releaseWorkOrders.size() > 0){
        insert releaseWorkOrders;
      }
    }
  }

  //private static void syncRelatedMWOs(Map<ID,QTT_Order__c> newMap, Map<ID,QTT_Order__c> oldMap){
  private static void syncRelatedMWOs(Set<String> syncMWOOrderIds){
    // check if ServiceMax is disabled
    Boolean getOut = checkServiceMaxDisabled();
    if (getOut){
      return;
    }

    Set<String> mWOIDs = new Set<String>(); // define collection of master work order ids

    String objName = 'QTT_Order__c';
    String selectOrders  = 'SELECT ';
    selectOrders += buildQueryStringForObject(objName);
    List<String> valueList = new List<String>(syncMWOOrderIds);

    selectOrders += ' FROM '+objName+' WHERE Id IN (\''+String.join(valueList,'\',\'')+'\')';
    System.debug('selectOrders is: '+selectOrders);

    List<QTT_Order__c> qOrderList = Database.query(selectOrders);

    Map<Id,QTT_Order__c> qOrderMap = new Map<Id,QTT_Order__c>(qOrderList); 

    for (QTT_Order__c qOrd : qOrderList){

      if (String.isNotBlank(qOrd.Master_Work_Order__c)){
        mWOIDs.add(qOrd.Master_Work_Order__c);
      }
    }


    // if master work order ids were collected, get the MWOs and map them
    if (mWOIDs.size() > 0){

      List<Master_Work_Order__c> mWOsToUpdateList = new List<Master_Work_Order__c>();

      // build map of master work orders related to the QuoteOrders
      Map<ID,Master_Work_Order__c> mwoMap = new Map<ID,Master_Work_Order__c>([SELECT Id, Name, Order__c, Ordered_Revision__c, Primary_System__c
                                            , State__c, Target_Completion__c, QTT_Target_Completion_Date__c, Target_Release__c, Target_PreWire__c
                                            , Target_Startup__c, QTT_Target_Startup_Date__c, Blanket_Value__c, Cancelled__c
                                            , Estimated_Elective_Service_Hours__c, Estimated_Prewire_Hours__c
                                            , Estimated_SPV_Doc_Hours__c, Estimated_Startup_Hours__c, Estimated_Training_Hours__c
                                            FROM Master_Work_Order__c WHERE Id IN :mWOIDs]);

      // process master work orders
      if (mwoMap.size() > 0){

        Boolean mwoNeedsUpdate;
        for (Master_Work_Order__c mWO : mwoMap.values()){

          if (String.isNotBlank(mWO.Order__c) && ! mWO.Cancelled__c){

            // get the QuoteOrder related to the MWO
            QTT_Order__c qOrder = qOrderMap.get(mWO.Order__c);

            // sync required field values from QuoteOrder to MWO
            if (qOrder != null){

              mwoNeedsUpdate = false;
              mwoNeedsUpdate = (mWO.Blanket_Value__c != qOrder.Blanket_Value__c) ? true : mwoNeedsUpdate;
              mwoNeedsUpdate = (mWO.Estimated_SPV_Doc_Hours__c != qOrder.Estimated_SPV_Doc_Hours__c) ? true : mwoNeedsUpdate;
              mwoNeedsUpdate = (mWO.Estimated_Elective_Service_Hours__c != qOrder.Estimated_Elective_Service_Hours__c) ? true : mwoNeedsUpdate;
              mwoNeedsUpdate = (mWO.Estimated_Training_Hours__c != qOrder.Estimated_Training_Hours__c) ? true : mwoNeedsUpdate;
              mwoNeedsUpdate = (mWO.Estimated_Startup_Hours__c != qOrder.Estimated_Startup_Hours__c) ? true : mwoNeedsUpdate;
              mwoNeedsUpdate = (mWO.Estimated_Prewire_Hours__c != qOrder.Estimated_Prewire_Hours__c) ? true : mwoNeedsUpdate;
              mwoNeedsUpdate = (mWO.Target_Startup__c != qOrder.Target_Startup__c) ? true : mwoNeedsUpdate;
              mwoNeedsUpdate = (mWO.Target_Completion__c != qOrder.Target_Completion__c) ? true : mwoNeedsUpdate;
              mwoNeedsUpdate = (mWO.Target_Release__c != qOrder.Target_Release__c) ? true : mwoNeedsUpdate;
              mwoNeedsUpdate = (mWO.Target_PreWire__c != qOrder.Target_PreWire__c) ? true : mwoNeedsUpdate;

              if (mwoNeedsUpdate){
                
                setMWOValuesFromQuoteOrder(qOrder,mWO); // set Master Work Order fields from QuoteOrder field values
                mWOsToUpdateList.add(mWO);
              }
            }
          }
        }
        // update the Master Work Orders
        if (! mWOsToUpdateList.isEmpty()){

          update mWOsToUpdateList;
        }
      }
    }
  }

  private static void setMWOValuesFromQuoteOrder(QTT_Order__c qOrd, Master_Work_Order__c mWO){

    mWO.Name = qOrd.QTT_External_ID__c;
    mWO.Order__c = qOrd.Id;
    mWO.Ordered_Revision__c = qOrd.Ordered_Revision__c;
    mWO.Primary_System__c = qOrd.Primary_System__c;
    mWO.Blanket_Value__c = qOrd.Blanket_Value__c;
    mWO.Estimated_SPV_Doc_Hours__c = qOrd.Estimated_SPV_Doc_Hours__c;
    mWO.Estimated_Elective_Service_Hours__c = qOrd.Estimated_Elective_Service_Hours__c;
    mWO.Estimated_Training_Hours__c = qOrd.Estimated_Training_Hours__c;
    mWO.Estimated_Startup_Hours__c = qOrd.Estimated_Startup_Hours__c;
    mWO.Estimated_Prewire_Hours__c = qOrd.Estimated_Prewire_Hours__c;
    mWO.QTT_Target_Startup_Date__c = qOrd.Target_Startup__c;
    mWO.QTT_Target_Completion_Date__c = qOrd.Target_Completion__c;
    mWO.Target_Release__c = qOrd.Target_Release__c;
    mWO.Target_PreWire__c = qOrd.Target_PreWire__c;
    mWO.City__c = qOrd.QTT_QuoteJobCity__c;
    mWO.State__c = qOrd.QTT_QuoteJobState__c;
    mWO.Target_Startup__c = qOrd.Target_Startup__c;
    mWO.Country__c = qOrd.QTT_QuoteJobCountry__c;
  }

  public static Boolean checkAllTriggersDisabled(){
    String setting = 'DISABLE ALL TRIGGERS';
    Boolean result = checkQttTriggerSetting(setting);
    return result;
    }

  private static Boolean checkServiceMaxDisabled(){
    String setting = 'Disable ServiceMax Data';
    Boolean result = checkQttTriggerSetting(setting);
    return result;
    }

  private static Boolean checkOpportunitiesDisabled(){
    String setting = 'Disable Opportunity Processing';
    Boolean result = checkQttTriggerSetting(setting);
    return result;
    }

  private static Boolean checkQttTriggerSetting(String setting){
    Boolean runStatus = True;
    Map<String,QTT_Trigger_Settings__c> settingsMap = QTT_Trigger_Settings__c.getall();
    if (String.isNotBlank(setting)){
      QTT_Trigger_Settings__c mySetting = settingsMap.get(setting);
      if (mySetting != null){
        runStatus = mySetting.Set__c;
      }
    }
    return runStatus;
  }

  private static void applyBusinessRules(Master_Work_Order__c mWO, String release, List<Business_Rules__c> busRules){
    Master_Work_Order__c mw = mWO;
    String rel = release;
    Boolean applyBusRules = false;

    // Attempt to apply Release0 business rules only when both prewire & startup target dates are blank
    // Attempt to apply Release1 business rules only when target startup date is blank
    if (rel == 'Release0' && mw.Target_PreWire__c == null && mw.QTT_Target_Startup_Date__c == null){

      applyBusRules = true;

    } else if (rel == 'Release1' && mw.QTT_Target_Startup_Date__c == null){

      applyBusRules = true;
    }

    if (applyBusRules){

      Business_Rules__c stateRule;
      Business_Rules__c allStates;
      Decimal mwo_Blanket;
      Decimal br_Blanket;

      // get numeric value of Master Work Order Blanket Value
      if (mw.Blanket_Value__c == null){
        mwo_Blanket = 0;
      } else {
        mwo_Blanket = mw.Blanket_Value__c * 1;
      }

      // Look for state specific and non-state specific business rules that may apply
      for (Business_Rules__c br : busRules){

        // only consider business rules matching the System Type
      if (br.System_Type__c == mw.Primary_System__c){

        // get numeric value of Business Rule Blanket Value
          if (br.Blanket_Value__c == null){
            br_Blanket = 0;
          } else {
            br_Blanket = br.Blanket_Value__c * 1;
          }

          // if Business Rule based on Greater or equal
          if (br.Value_Comparison__c == 'Greater or equal'){

             if (mwo_Blanket >= br_Blanket){

              if (br.Job_Location_State__c == mw.State__c){

                stateRule = br;

              } else if (br.Job_Location_State__c == 'All States'){

                allStates = br;
              }
             }

          // otherwise, if Business Rule is based on Less or equal
          } else if (br.Value_Comparison__c == 'Less or equal'){

            if (mwo_Blanket <= br_Blanket) {

              if (br.Job_Location_State__c == mw.State__c){

                stateRule = br;

              } else if (br.Job_Location_State__c == 'All States'){

                allStates = br;
              }
            }

          // otherwise, if Business Rule is based on Less than
          } else if (br.Value_Comparison__c == 'Less than'){

            if (mwo_Blanket < br_Blanket){

              if (br.Job_Location_State__c == mw.State__c){

                stateRule = br;

              } else if (br.Job_Location_State__c == 'All States'){

                allStates = br;
              }
            }
          }
      }
      }

      // Determine if state specific or non-state specific business rule applies
      if (stateRule != null || allStates != null){
        Date preWire = Date.today();
        Date preCon = Date.today();
        Date intCon = Date.today();
        Date startUp = Date.today();
        //Integer daysToAdd = 0;

        if (stateRule != null){
          mw.Business_Rule_Applied__c = stateRule.Id;

          if (rel == 'Release0'){

            preWire = getTargetDate(preWire, stateRule.Release_0_Target_Prewire_Date__c);

            preCon = getTargetDate(preCon, stateRule.of_Days_from_HFR_Pre_Construction__c);

            intCon = getTargetDate(intCon, stateRule.of_Days_from_HFR_Integration_Consult__c);

          } else if (rel == 'Release1'){

            startUp = getTargetDate(startUp, stateRule.Release_1_to_Startup_Days__c);
          }

        } else if (allStates != null){
          mw.Business_Rule_Applied__c = allStates.Id;

          if (rel == 'Release0'){

            preWire = getTargetDate(preWire, allStates.Release_0_Target_Prewire_Date__c);

            preCon = getTargetDate(preCon, allStates.of_Days_from_HFR_Pre_Construction__c);

            intCon = getTargetDate(intCon, allStates.of_Days_from_HFR_Integration_Consult__c);

          } else if(rel == 'Release1'){

            startUp = getTargetDate(startUp, allStates.Release_1_to_Startup_Days__c);
          }
        }

        if (rel == 'Release0'){

          mw.Target_PreWire__c = preWire;
          mw.Target_PreConstruction__c = preCon;
          mw.Target_Integration_Consultation__c = intCon;

        } else if (rel == 'Release1'){

          mw.Target_Startup__c = startUp;
        }
      }

    }
  }

  private static Date getTargetDate(Date beginDate, Decimal addDays){
    // add requested number of days to beginning date and return the new date if it is a Monday
    // otherwise return the following Monday after the new date

    Integer daysToAdd = (addDays == null) ? 0 : (Integer) addDays;

    Date origDate = (beginDate == null) ? Date.today() : beginDate;
    origDate = origDate.addDays(daysToAdd);

    Date monday = Date.newInstance(2000, 05, 29);

    Integer origDayOfWeek = Math.mod(monday.daysBetween(origDate), 7);

    Date targetDate = (origDayOfWeek == 0) ? origDate : origDate.addDays(7 - origDayOfWeek);

    return targetDate;
  }

  private static Boolean syncOppFromQuoteOrder(QTT_Order__c quoteOrder, Opportunity oppToSync, Boolean firstTimeLink){
    // define return variable
    Boolean oppSyncRequired = false;

    // define variables for Quote Order and Opportunity
    QTT_Order__c qOrd = quoteOrder;
    Opportunity opp = oppToSync;

    // set the default Close Date for all new Opportunities
    Date defaultCloseDate = Date.today() + 60;

    // if QuoteOrder has reached Release0 or Release1, set Forecast to 100%
    if ((qOrd.QTT_Order_Status__c == 'HFR' || qOrd.QTT_Order_Status__c == 'Partial' || qOrd.QTT_Order_Status__c == 'Released') && opp.Forecast_Lutron__c != '100%'){

      opp.Forecast_Lutron__c = '100%';
      oppSyncRequired = true;
      System.debug('oppSyncRequired: '+oppSyncRequired);
    }

    if (String.isBlank(opp.Id)){ // **BEGIN: FIELD UPDATES FOR NEW OPPORTUNITIES ONLY**

      opp.Name = (qOrd.QTT_Quote_Order_Name__c != null) ? qOrd.QTT_Quote_Order_Name__c : 'Quote Order Name not sent from QTT'; // set Opp Name from QuoteOrder QTT_Quote_Order_Name__c; if null, use a default value
      opp.CloseDate = defaultCloseDate; // set Opp Close Date to the default value
      opp.QTT_Integration_Status__c = 'Ready to Integrate';

      // 2/29/2016; J.Aquino/ForeFront
      //opp.StageName = String.isBlank(qOrd.Stage__c) ? 'Out to Bid/Tender' : qOrd.Stage__c; // set Opp Stage from QuoteOrder QTT_Quote_Stage; if null, use "Out to Bid/Tender" as the default value
      if (qOrd.QTT_Order_Status__c == 'HFR'){
        opp.StageName = 'Won - Hold For Release';
      } else if (qOrd.QTT_Order_Status__c == 'Partial' || qOrd.QTT_Order_Status__c == 'Released'){
        opp.StageName = 'Won - Released';
      } else if (String.isBlank(qOrd.Stage__c)){
        opp.StageName = 'Out to Bid/Tender';
      } else {
        opp.StageName = qOrd.Stage__c;
      }

      opp.Created_From_QTT_Integration__c = true;
      opp.AccountId = qOrd.Account__c; // set Opp Account from QuoteOrder Account
      oppSyncRequired = true;
      System.debug('oppSyncRequired: '+oppSyncRequired);
      System.debug('opp is : '+opp);

      // **END: FIELD UPDATES FOR NEW OPPORTUNITIES ONLY**

    } else { // **BEGIN: FIELD UPDATES FOR EXISTING OPPORTUNITIES ONLY**

      if (qOrd.QTT_Order_Date__c != null){ // if QuoteOrder has a QTT_Order_Date

        if (opp.CloseDate != qOrd.QTT_Order_Date__c){ // if Opp CloseDate doesn't match QuoteOrder QTT_Order_Date

          opp.CloseDate = qOrd.QTT_Order_Date__c; // set Opp Close Date from QuoteOrder QTT_Order_Date
          oppSyncRequired = true;
          System.debug('oppSyncRequired: '+oppSyncRequired);
        }
      }

      // if QuoteOrder stage is 'Won - Hold For Release' or 'Won - Released' or if this is the first time linking to an existing opportunity
      if ((qOrd.StageName__c == 'Won - Hold For Release' || qOrd.StageName__c == 'Won - Released') && opp.StageName != qOrd.StageName__c){

        opp.StageName = qOrd.StageName__c; // set Opp Stage from QuoteOrder Stage
        oppSyncRequired = true;
        System.debug('oppSyncRequired: '+oppSyncRequired);

      } else if (firstTimeLink){

        if (String.isBlank(qOrd.Stage__c)){ // if QTT did not send a Quote Stage

          opp.StageName = 'Out to Bid/Tender'; // use default Opportunity Stage
          oppSyncRequired = true;
          System.debug('oppSyncRequired: '+oppSyncRequired);

        } else { // if QTT sent a Quote Stage

          Map<String,QTTOpportunityStage__c> stageMap = new Map<String,QTTOpportunityStage__c>(); // define map for custom setting that translates QTT Stage to SFDC Stage
          stageMap = QTTOpportunityStage__c.getAll();
          if (stageMap.containsKey(qOrd.Stage__c)){
            opp.StageName = stageMap.get(qOrd.Stage__c).SFDCStage__c; // lookup the QTT stage in the custom setting and use the SFDC Stage found in the custom setting
          }
          opp.StageName = (opp.StageName == null) ? 'Out to Bid/Tender' : opp.StageName; // if QTT stage was not found in the custom setting use the default Opportunity Stage
          oppSyncRequired = true;
          System.debug('oppSyncRequired: '+oppSyncRequired);
        }
      }
    } // **END: FIELD UPDATES FOR EXISTING OPPORTUNITIES ONLY**

    // **BEGIN: FIELD UPDATES THAT ARE DONE UNDER SPECIAL CONDITIONS**
    if (qOrd.StageName__c == 'Won - Hold For Release' || qOrd.StageName__c == 'Won - Released'){ // if it is an "order"

      if (opp.Amount != qOrd.Blanket_Value__c){

        opp.Amount = qOrd.Blanket_Value__c; // set Opp Amount from QuoteOrder Blanket Value
        oppSyncRequired = true;
        System.debug('oppSyncRequired: '+oppSyncRequired);
      }

      if (opp.CurrencyIsoCode != qOrd.CurrencyIsoCode){ 

        opp.CurrencyIsoCode = qOrd.CurrencyIsoCode; // set Opp Currency from QuoteOrder Currency
        oppSyncRequired = true;
        System.debug('oppSyncRequired: '+oppSyncRequired);
      }
    }

    if (String.isBlank(opp.Installation_Type__c)){

      opp.Installation_Type__c = qOrd.QTT_Job_Type__c; // set Opp Installation Type from QuoteOrder QTT_Job_Type
      oppSyncRequired = true;
      System.debug('oppSyncRequired: '+oppSyncRequired);
    }

    if (String.isBlank(opp.Vertical_Market__c)){

      opp.Vertical_Market__c = qOrd.QTT_Vertical_Market__c; // set Opp Vertical Market from QuoteOrder QTT_Vertical_Market
      oppSyncRequired = true;
      System.debug('oppSyncRequired: '+oppSyncRequired);
    }

    if (String.isBlank(opp.Construction_Type__c)){

      opp.Construction_Type__c = qOrd.QTT_Construction_Type__c; // set Opp Construction Type from QuoteOrder QTT_Construction_Type
      oppSyncRequired = true;
      System.debug('oppSyncRequired: '+oppSyncRequired);
    }
    // **END: FIELD UPDATES THAT ARE DONE UNDER SPECIAL CONDITIONS**

    // **BEGIN: FIELD UPDATES THAT ARE DONE ONLY IF OUT OF SYNC**
    if (opp.Job_Number__c != qOrd.QTT_Job_Number__c){

      opp.Job_Number__c = qOrd.QTT_Job_Number__c; // set Opp Job Number from QuoteOrder QTT_Job_Number
      oppSyncRequired = true;
      System.debug('oppSyncRequired: '+oppSyncRequired);
    }

    if (opp.Job__c != qOrd.Job_Number__c){

      opp.Job__c = qOrd.Job_Number__c; // set Opp Job from Quote Order Job Number
      oppSyncRequired = true;
      System.debug('oppSyncRequired: '+oppSyncRequired);
    }

    if (opp.State__c != qOrd.QTT_QuoteJobState__c){

      opp.State__c = qOrd.QTT_QuoteJobState__c; // set Opp State from QuoteOrder QTT_QuoteJobState
      oppSyncRequired = true;
      System.debug('oppSyncRequired: '+oppSyncRequired);
    }

    if (opp.City__c != qOrd.QTT_QuoteJobCity__c){

      opp.City__c = qOrd.QTT_QuoteJobCity__c; // set Opp City from QuoteOrder QTT_QuoteJobCity
      oppSyncRequired = true;
      System.debug('oppSyncRequired: '+oppSyncRequired);
    }

    if (opp.Country__c != qOrd.QTT_QuoteJobCountry__c){

      opp.Country__c = qOrd.QTT_QuoteJobCountry__c; // set Opp Country from QuoteOrder QTT_QuoteJobCountry
      oppSyncRequired = true;
      System.debug('oppSyncRequired: '+oppSyncRequired);
    }

    if (opp.QTT_Quote_Name__c != qOrd.QTT_Quote_Order_Name__c){

      opp.QTT_Quote_Name__c = qOrd.QTT_Quote_Order_Name__c; // set Opp QTT Quote Name from QuoteOrder QTT_Quote_Order_Name
      oppSyncRequired = true;
      System.debug('oppSyncRequired: '+oppSyncRequired);
    }

    if (opp.QTT_Target_Completion_Date__c != qOrd.Target_Completion__c){

      opp.QTT_Target_Completion_Date__c = qOrd.Target_Completion__c; // set Opp QTT Target Completion Date from QuoteOrder Target Completion
      oppSyncRequired = true;
      System.debug('oppSyncRequired: '+oppSyncRequired);
    }

    if (opp.QTT_Target_Release_Date__c != qOrd.Target_Release__c){

      opp.QTT_Target_Release_Date__c = qOrd.Target_Release__c; // set Opp QTT Target Release Date from QuoteOrder Target Release
      oppSyncRequired = true;
      System.debug('oppSyncRequired: '+oppSyncRequired);
    }

    if (opp.QTT_Target_PreWire_Date__c != qOrd.Target_PreWire__c){

      opp.QTT_Target_PreWire_Date__c = qOrd.Target_PreWire__c; // set Opp QTT Target PreWire Date from QuoteOrder Target PreWire
      oppSyncRequired = true;
      System.debug('oppSyncRequired: '+oppSyncRequired);
    }

    if (opp.QTT_Target_StartUp_Date__c != qOrd.Target_Startup__c){

      opp.QTT_Target_StartUp_Date__c = qOrd.Target_Startup__c; // set Opp QTT Target StartUp Date from QuoteOrder Target Startup
      oppSyncRequired = true;
      System.debug('oppSyncRequired: '+oppSyncRequired);
    }

    if (opp.Primary_System__c != qOrd.Primary_System__c){

      opp.Primary_System__c = qOrd.Primary_System__c; // set Opp Primary System from QuoteOrder Primary System
      oppSyncRequired = true;
      System.debug('oppSyncRequired: '+oppSyncRequired);
    }

    if (opp.QTT_Quote_Number__c != qOrd.QTT_Quote_RID__c){

      opp.QTT_Quote_Number__c = qOrd.QTT_Quote_RID__c; // set Opp QTT Quote Number from QuoteOrder QTT_Quote_RID
      oppSyncRequired = true;
      System.debug('oppSyncRequired: '+oppSyncRequired);
    }

    if (opp.QTT_RID__c != qOrd.QTT_Opportunity_RID__c){

      opp.QTT_RID__c = qOrd.QTT_Opportunity_RID__c; // set Opp QTT RID from QuoteOrder QTT _Opportunity _RID
      oppSyncRequired = true;
      System.debug('oppSyncRequired: '+oppSyncRequired);
    }

    if (opp.Bid_Date__c != qOrd.QTT_Bid_Date__c){

      opp.Bid_Date__c = qOrd.QTT_Bid_Date__c; // set Opp Bid Date from QuoteOrder QTT_Bid_Date
      oppSyncRequired = true;
      System.debug('oppSyncRequired: '+oppSyncRequired);
    }

    /*if (opp.Lutron_Rep__c != qOrd.QTT_Opp_Rep_Account__c){

      opp.Lutron_Rep__c = qOrd.QTT_Opp_Rep_Account__c; // set Opp Lutron Rep from QuoteOrder QTT_Opp_Rep_Account
      oppSyncRequired = true;
      System.debug('oppSyncRequired: '+oppSyncRequired);
    }*/

    /*if (opp.Share_with_Lutron_Rep__c != qOrd.QTT_Opp_Share_With_Rep__c){

      opp.Share_with_Lutron_Rep__c = qOrd.QTT_Opp_Share_With_Rep__c; // set Opp Share with Lutron Rep from QuoteOrder QTT_Opp_Share_With_Rep
      oppSyncRequired = true;
      System.debug('oppSyncRequired: '+oppSyncRequired);
    }*/

    if (opp.QTT_PM_Job_Status__c != qOrd.Job_Status__c){

      opp.QTT_PM_Job_Status__c = qOrd.Job_Status__c; // set Opp QTT PM Job Status from QuoteOrder Job Status
      oppSyncRequired = true;
      System.debug('oppSyncRequired: '+oppSyncRequired);
    }

    if (opp.QTT_Order_Status__c != qOrd.QTT_Order_Status__c){

      opp.QTT_Order_Status__c = qOrd.QTT_Order_Status__c; // set Opp QTT Order Status from QuoteOrder QTT_Order_Status
      oppSyncRequired = true;
      System.debug('oppSyncRequired: '+oppSyncRequired);
    }

    if (opp.QTT_Project_Manager__c != qOrd.Project_Manager_Name__c){

      opp.QTT_Project_Manager__c = qOrd.Project_Manager_Name__c; // set Opp QTT Project Manager from QuoteOrder Project Manager Name
      oppSyncRequired = true;
      System.debug('oppSyncRequired: '+oppSyncRequired);
    }

    if (opp.QTT_Project_Name__c != qOrd.Job_Name__c){

      opp.QTT_Project_Name__c = qOrd.Job_Name__c; // set Opp QTT Project Name from QuoteOrder Job Name
      oppSyncRequired = true;
      System.debug('oppSyncRequired: '+oppSyncRequired);
    }

    if (opp.QTT_Project_Number__c != qOrd.QTT_ProjectID__c){

      opp.QTT_Project_Number__c = qOrd.QTT_ProjectID__c; // set Opp QTT Project Number from QuoteOrder QTT_ProjectID
      oppSyncRequired = true;
      System.debug('oppSyncRequired: '+oppSyncRequired);
    }
    // **END: FIELD UPDATES THAT ARE DONE ONLY IF OUT OF SYNC**

    /*
    *** JA; 2/10/2016; moved this code to cancelOrder() method
    //JC/FF 2-2-2016 update from LS-341
    if (qOrd.Stage__c == 'Cancelled System Order') {
        opp.StageName = 'Out to Bid/Tender';
        oppSyncRequired = true;
    }
    *** JA; 2/10/2016 
    */ 

    return oppSyncRequired;
  }

  private static void createReleaseZeroLocations(Set<String> releaseZeroQuoteOrderIds){

    // Get the record type id for Standard Locations
    Schema.SObjectType s = SVMXC__Site__c.sObjectType;
    Schema.DescribeSObjectResult resSchema = s.getDescribe();
    Map<String,Schema.RecordTypeInfo> recordTypeInfo = resSchema.getRecordTypeInfosByName(); //get all Recordtypes for the Sobject
    Id stdLocRtId = recordTypeInfo.get('Standard Location').getRecordTypeId(); //get the particular RecordId by Name

    // init map of Locations by name
    Map<String,SVMXC__Site__c> newLocationsByNameMap = new Map<String,SVMXC__Site__c>();

    // get list of QuoteOrders
    List<QTT_Order__c> qOrderList = new List<QTT_Order__c>([SELECT Id, Name, QTT_Quote_Order_Name__c, Job_Number__c, QTT_Job_Number__c,
                                Primary_System__r.Name, QTT_QuoteJobCity__c, QTT_QuoteJobState__c, QTT_QuoteJobCountry__c
                                FROM QTT_Order__c WHERE Id IN :releaseZeroQuoteOrderIds]);

    // process QuoteOrders and collect location names to link to or add
    for (QTT_Order__c qOrd : qOrderList){

      SVMXC__Site__c newLoc = new SVMXC__Site__c();
      newLoc = setLocationValuesFromQuoteOrder(newLoc,qOrd);
      newLoc.RecordTypeId = stdLocRtId;

      // add new location to map
      newLocationsByNameMap.put(newLoc.Name.toUpperCase(), newLoc);
    }

    // get existing locations with matching names
    Map<ID,SVMXC__Site__c> currentLocationsMap = new Map<ID,SVMXC__Site__c>([SELECT Id, Name FROM SVMXC__Site__c WHERE Name IN :newLocationsByNameMap.keySet()]);

    // process existing locations and if found in new map, remove it so a duplicate will not be created
    for (ID locID : currentLocationsMap.keySet()){

      SVMXC__Site__c currLoc = currentLocationsMap.get(locID);

      newLocationsByNameMap.remove(currLoc.Name.toUpperCase());
    }

    // if new locations still left in new map, create them
    if (newLocationsByNameMap.size() > 0){

      insert newLocationsByNameMap.values();
    }
  }

  private static void createReleaseZeroInstalledProducts(List<QTT_Order__c> releaseZeroOrders){
    // 2/25/2016; J.Aquino/ForeFront; LS-396
    // changed input @param into this method. Previous input was (Set<String> releaseZeroQuoteOrderIds)
    // changed to use QuoteOrder data instead of MWO data to create the Installed Products since the Installed Product will now be created before the MWO
    System.debug('releaseZeroOrders are: '+releaseZeroOrders);
    // init list of new Installed products to add
    List<SVMXC__Installed_Product__c> iProdsToAdd = new List<SVMXC__Installed_Product__c>();

    // 2/25/2016; J.Aquino/ForeFront; LS-396
    /*List<Master_Work_Order__c> releaseZeroMWOList = new List<Master_Work_Order__c>([SELECT Id, Name, Location__c, Primary_System__c, Primary_System__r.Name, Quote_Name__c, Country__c,
                                                                                      Job__c, City__c, State__c, Installed_Product__c FROM Master_Work_Order__c
                                                                                      WHERE Order__c IN :releaseZeroQuoteOrderIds
                                                                                      AND Id NOT IN (SELECT Master_Work_Order__c FROM SVMXC__Installed_Product__c)]);*/

    if (! releaseZeroOrders.isEmpty()){

      Map<String,SVMXC__Installed_Product__c> iProdNameMap = getInstalledProductsFromQuoteOrders(releaseZeroOrders); // get existing Installed Products with matching name based on Lutron's naming standard

      Map<String,SVMXC__Site__c> locationNameMap = getLocationsFromQuoteOrders(releaseZeroOrders); // get existing locations with matching name based on Lutron's naming standard
      System.debug('locationNameMap is :'+locationNameMap);

      for (QTT_Order__c qOrd : releaseZeroOrders){

        String iProdName = qOrd.QTT_External_ID__c+'_'+qOrd.PrimarySystemName__c; // set the name to lookup based on Lutron's naming convention

        SVMXC__Installed_Product__c iProd = iProdNameMap.get(iProdName); // get the installed product from the map
        System.debug('iProd is: '+iProd);
        if (iProd == null){ // if the IP was not found in the map create a new one

          iProd = new SVMXC__Installed_Product__c();
          iProd.Name = qOrd.QTT_External_ID__c+'_'+qOrd.PrimarySystemName__c;
          iProd.SVMXC__City__c = qOrd.QTT_QuoteJobCity__c;
          iProd.SVMXC__Country__c = qOrd.QTT_QuoteJobCountry__c;
          iProd.Job__c = qOrd.Job_Number__c;
          iProd.SVMXC__Product__c = qOrd.Primary_System__c;
          iProd.SVMXC__State__c = qOrd.QTT_QuoteJobState__c;

        String locName = setStandardLocationName(qOrd.QTT_Quote_Order_Name__c,qOrd.QTT_QuoteJobCity__c,qOrd.QTT_QuoteJobState__c); //derive the standard location name
        System.debug('locName is: '+locName+'; locName.toUpperCase() is: '+locName.toUpperCase());
        if (String.isNotBlank(locName) && locationNameMap.containsKey(locName.toUpperCase())){

          iProd.SVMXC__Site__c = locationNameMap.get(locName.toUpperCase()).Id; // attempt to set the location id on the Installed Product by looking up in location map by name
        }

        iProdsToAdd.add(iProd);
        System.debug('iProd is: '+iProd);
        }
      }

      if (iProdsToAdd.size() > 0){

        insert iProdsToAdd;
      }
    }

  }

  private static SVMXC__Site__c setLocationValuesFromQuoteOrder(SVMXC__Site__c aLocation, QTT_Order__c qOrder){

    SVMXC__Site__c aLoc = aLocation;
    QTT_Order__c qOrd = qOrder;

    // set location name per Lutron's naming standard
    aLoc.Name = setStandardLocationName(qOrd.QTT_Quote_Order_Name__c,qOrd.QTT_QuoteJobCity__c,qOrd.QTT_QuoteJobState__c);

    // set additional field values from QuoteOrder
    aLoc.Job__c = qOrd.Job_Number__c;
    aLoc.SVMXC__City__c = qOrd.QTT_QuoteJobCity__c;
    aLoc.SVMXC__State__c = qOrd.QTT_QuoteJobState__c;
    aLoc.SVMXC__Country__c = qOrd.QTT_QuoteJobCountry__c;

    return aLoc;
  }

  private static String setStandardLocationName(String quoteName, String cityName, String stateCode){

    // define location name to return
    String locName = null;

    // if QuoteOrder has a text name, derive the location name
    if (String.isNotBlank(quoteName)){

      /* make sure the final concatenated name does not exceed 80 characters, as this
      *  will cause the insert/update to fail.
      *  Lutron has decided to use 55 characters max of the Quote name, leaving
      *  the remaining 25 characters available to append the City_State
      */

      Integer maxLength = (quoteName.length() > 55) ? 55 : quoteName.length();

      String quote55 = quoteName.substring(0,maxLength);

      String cityComponent = (String.isNotBlank(cityName)) ? '_'+cityName : '' ;

      String stateComponent = (String.isNotBlank(stateCode)) ? '_'+stateCode : '';

      String mashUp = quote55 + cityComponent + stateComponent;

      maxLength = (mashUp.length() > 80) ? 80 : mashUp.length();

      locname = mashUp.substring(0,maxLength);
    }

    return locName;
  }

  private static Map<String,SVMXC__Site__c> getLocationsFromQuoteOrders(List<QTT_Order__c> qOrders){

    // define map that will return Locations keyed by name
    Map<String,SVMXC__Site__c> locationNameMap = new Map<String,SVMXC__Site__c>();

    // define collection of Location names derived from the QuoteOrders
    Set<String> locNames = new Set<String>();

    // define list of Locations with matching names
    List<SVMXC__Site__c> locs = new List<SVMXC__Site__c>();

    String locName;

    // process QuoteOrders and take names
    for (QTT_Order__c qOrd : qOrders){

      if (String.isNotBlank(qOrd.QTT_Quote_Order_Name__c)){

        // get standard location name
        locName = setStandardLocationName(qOrd.QTT_Quote_Order_Name__c,qOrd.QTT_QuoteJobCity__c,qOrd.QTT_QuoteJobState__c);
        locNames.add(locName.toUpperCase());
      }
    }

    // if collection has names, build the map
    if (locNames.size() > 0){

      // get Locations with matching names
      locs = [SELECT id, Name FROM SVMXC__Site__c WHERE Name IN :locNames];

      // build map of Locations keyed by name
      for (SVMXC__Site__c loc : locs){

        locationNameMap.put(loc.Name.toUpperCase(), loc);
      }
    }

    return locationNameMap;
  }

  private static Map<String,SVMXC__Installed_Product__c> getInstalledProductsFromQuoteOrders(List<QTT_Order__c> qOrders){

    // define map that will return Installed Products keyed by name
    Map<String,SVMXC__Installed_Product__c> iProdNameMap = new Map<String,SVMXC__Installed_Product__c>();

    // define collection of Installed Product names derived from the QuoteOrders
    Set<String> iProdNames = new Set<String>();

    // define list of Installed Products with matching names
    List<SVMXC__Installed_Product__c> iProds = new List<SVMXC__Installed_Product__c>();

    // process QuoteOrders and take names
    for (QTT_Order__c qOrd : qOrders){

      if (String.isNotBlank(qOrd.Primary_System__c)){

        // get standard Installed Product name
        iProdNames.add(qOrd.QTT_External_ID__c+'_'+qOrd.PrimarySystemName__c);
      }
    }

    // if collection has names, build the map
    if (iprodNames.size() > 0){

      // get Installed Products with matching names
      iProds = [SELECT id, Name FROM SVMXC__Installed_Product__c WHERE Name IN :iProdNames];

      // build map of Locations keyed by name
      for (SVMXC__Installed_Product__c iProd : iProds){

        iProdNameMap.put(iProd.Name,iProd);
      }
    }

    return iProdNameMap;
  }

  /*private static void setQuoteOrderOwner(List<QTT_Order__c> qOrders, Set<ID> oppIDs){

    // if opp ids were collected, build map of opportunities to lookup the owner
    if (oppIDs.size() > 0){

      // build map of related opportunities only where the owner is an active user
      Map<ID,Opportunity> oppMap = new Map<ID,Opportunity>([SELECT Id, OwnerId FROM Opportunity WHERE Id IN :oppIDs AND Owner.IsActive = True]);

      // process Quote Orders and set owner same as the Opportunity
      for (QTT_Order__c qOrd : qOrders){

        if (String.isNotBlank(qOrd.Opportunity__c)){

          Opportunity opp = oppMap.get(qOrd.Opportunity__c);

          if (opp != null){

            qOrd.OwnerId = opp.OwnerId;
          }
        }
      }
    }
  }*/

  private static void setPrimarySystem(List<QTT_Order__c> qOrders, Set<String> sModels){
    System.debug('sModels is: ' + sModels);
    if (sModels.size() > 0){

      // get list of Products
      List<Product2> pList = new List<Product2>([SELECT Id, Name, Primary_System__c FROM Product2 WHERE Name IN :sModels]);
      System.debug('pList is: ' + pList);
      if (pList.size() > 0){ // if products where found

        Map<String,Product2> pMap = new Map<String,Product2>(); // define map of products keyed by name

        for (Product2 prod : pList){ // iterate list of products

          if (String.isNotBlank(prod.Primary_System__c)){ // if product has a primary system

            pMap.put(prod.Name, prod); // add it to the map
          }
        }

        if (pMap.size() > 0){ // if map has products, process quote orders and get the Primary System

          for (QTT_Order__c qOrd : qOrders){ // iterate list of quote orders

            if (String.isNotBlank(qOrd.QTT_Startup_Model__c)){ // if the quote order has a startup model number

              Product2 p = pMap.get(qOrd.QTT_Startup_Model__c); // get the startup model from the map

              if (p != null){ // if startup model exists in the map

                qOrd.Primary_System__c = p.Primary_System__c; // set the Quote Order prmary system form the startup model
              }
            } else { // if the quote order does not have a startup model

              qOrd.Primary_System__c = null; // set the quote order primary system to null
            }
          }
        }
      }
    }
  }

  private static void autoGenContracts(Set<ID> qOIDs){

    if (! qOIDs.isEmpty()){ // if QuoteOrder ids were passed to the method 

      List<SVMXC__Service_Contract__c> contractList = new List<SVMXC__Service_Contract__c>(); // define list of contracts to add
      Set<String> partNumbers = new Set<String>(); // defne collection of TSP & Contract part numbers
      Set<Id> mwoIDs = new Set<Id>(); // define collection of MWO ids

      List<QTT_Order__c> qOrderList = new List<QTT_Order__c>([SELECT Id, Master_Work_Order__c FROM QTT_Order__c WHERE Id IN :qOIDs]); // get QuoteOrders that may need contracts

      if (! qOrderList.isEmpty()){ // if QuoteOrders were found

        for (QTT_Order__c q : qOrderList){ // iterate thru QuoteOrders

          if (String.isNotBlank(q.Master_Work_Order__c)){ // if QuoteOrder has a MasterWorkOrder
            mwoIDs.add(q.Master_Work_Order__c); // add the MWO id to the collection
          }
        }

        if (! mwoIDs.isEmpty()){ // if Master Work Order ids were collected

          // get QuoteOrders that don't already have a contract associated to their related MWO
          List<QTT_Order__c> qOrders = new List<QTT_Order__c>([SELECT Id, TSP_Part_Number__c, Contract_Part_Number__c, Master_Work_Order__c,
                                                                QTT_External_ID__c, TSP_Term__c, TSP_Value__c, Account__c, Contract_Term__c,
                                                                Contract_Value__c FROM QTT_Order__c WHERE Id IN :qOIDs
                                                                AND Master_Work_Order__c NOT IN (SELECT Master_Work_Order__c FROM SVMXC__Service_Contract__c WHERE Master_Work_Order__c IN :mwoIDs)]); 

          if (! qOrders.isEmpty()){ // if QuoteOrders without contracts were found

            for (QTT_Order__c qOrds : qOrders){ // iterate thru QuoteOrders

              if (String.isNotBlank(qOrds.TSP_Part_Number__c)){ // if QuoteOrder has a TSP part#
                partNumbers.add(qOrds.TSP_Part_Number__c); // add the TSP part# to the collection
              }

              if (String.isNotBlank(qOrds.Contract_Part_Number__c)){ // if QuoteOrder has a Contract part#
                partNumbers.add(qOrds.Contract_Part_Number__c); // add the Contract part# to the collection
              }
            }

            if (! partNumbers.isEmpty()){ // if any TSP or Contract part numbers were collected

              List<Product2> products = [SELECT Id, Name FROM Product2 WHERE Name IN: partNumbers]; //list of all products based on part numbers

              if (! products.isEmpty()){ // if products were found for the part numbers

                Map<String,Product2> prodMapByName = new Map<String,Product2>(); // define map of products keyed by name

                Set<Id> prodIDs = new Set<Id>(); // define collection of product ids

                for (Product2 p : products) {// iterate thru the products

                  prodIDs.add(p.Id); // add the product id for each part number to the collection
                  prodMapByName.put(p.Name, p); // add the product to the map
                }

                List<SVMXC__Service_Plan__c> servicePlans = [SELECT Id, Name, SVMXC__SLA_Terms__c, LSC_Product__c,
                                                                (SELECT Id, SVMXC__PM_Plan_Template__c FROM SVMXC__PM_Offerings__r) 
                                                            FROM SVMXC__Service_Plan__c WHERE LSC_Product__c IN :prodIDs]; // list of Service Plans related to the products (part numbers) from the QuoteOrders

                Map<String,SVMXC__Service_Plan__c> servPlanMapByProduct = new Map<String,SVMXC__Service_Plan__c>(); // define map of service plans keyed by product

                for (SVMXC__Service_Plan__c sPlan : servicePlans){ // iterate thru service plans

                  if (String.isNotBlank(sPlan.LSC_Product__c)){ // if service plan has a product

                    servPlanMapByProduct.put(sPlan.LSC_Product__c, sPlan); // add the service plan to the map
                  }
                }

                for (QTT_Order__c qOrd : qOrders){ //iterate thru QuoteOrders

                  if (String.isNotBlank(qOrd.TSP_Part_Number__c)){ // QuoteOrder has a TSP part number

                    Product2 tspProd = prodMapByName.get(qOrd.TSP_Part_Number__c); // lookup the TSP part number in the product map

                    if (tspProd != null){ // if the TSP part number was found in the map

                      SVMXC__Service_Plan__c servPlan = servPlanMapByProduct.get(tspProd.Id); // lookup the service plan by product

                      if (servPlan != null){ // if the service plan was found

                        SVMXC__Service_Contract__c newCon = new SVMXC__Service_Contract__c(); // create a new Contract
                        newCon.Name = qOrd.QTT_External_ID__c +'_'+servPlan.Name;
                        newCon.SVMXC__Service_Plan__c = servPlan.Id;
                        newCon.Contract_Term__c = qOrd.TSP_Term__c;
                        newCon.SVMXC__Contract_Price2__c = qOrd.TSP_Value__c;
                        newCon.SVMXC__Active__c = false;
                        newCon.SVMXC__Company__c = qOrd.Account__c;
                        newCon.SVMXC__Service_Level__c = servPlan.SVMXC__SLA_Terms__c;
                        newCon.Master_Work_Order__c = qOrd.Master_Work_Order__c;
                        newCon.SVMXC__Discount__c = 0;
                        contractList.add(newCon);
                      }
                    }
                  }

                  if (String.isNotBlank(qOrd.Contract_Part_Number__c)){ // QuoteOrder has a Contract part number

                    Product2 ctProd = prodMapByName.get(qOrd.Contract_Part_Number__c); // lookup the Contract part number in the product map

                    if (ctProd != null){ // if the Contract part number was found in the map

                      SVMXC__Service_Plan__c servPlan = servPlanMapByProduct.get(ctProd.Id); // lookup the service plan by product

                      if (servPlan != null){ // if the service plan was found

                        SVMXC__Service_Contract__c newCon = new SVMXC__Service_Contract__c(); // create a new Contract
                        newCon.Name = qOrd.QTT_External_ID__c+'_'+servPlan.Name;
                        newCon.SVMXC__Service_Plan__c = servPlan.Id;
                        newCon.Contract_Term__c = qOrd.Contract_Term__c;
                        newCon.SVMXC__Contract_Price2__c = qOrd.Contract_Value__c;
                        newCon.SVMXC__Active__c = false;
                        newCon.SVMXC__Company__c  = qOrd.Account__c;
                        newCon.SVMXC__Service_Level__c = servPlan.SVMXC__SLA_Terms__c;
                        newCon.Master_Work_Order__c = qOrd.Master_Work_Order__c;
                        newCon.SVMXC__Discount__c = 0;
                        contractList.add(newCon);
                      }
                    }
                  }
                }
                insert contractList;
                System.debug(contractList);
                // Covered Product and Covered Location are child objects of SVMXC__Service_Contract__c, these fields can't be accessed after the contracts are created
                // iterate over the contractlist then create the children and populate the relevant fields
                
                // 2/25/2016; J.Aquino/ForeFront; LS-396; replaced soql below to remove subquery of Installed Product related list
                // List<Master_Work_Order__c> mWOs = [SELECT Id, Location__c,  (SELECT Id FROM Installed_Products__r LIMIT 1) FROM Master_Work_Order__c WHERE Id IN: mwoIDs];

                //List<Master_Work_Order__c> mWOs = [SELECT Id, Location__c, Installed_Product__c FROM Master_Work_Order__c WHERE Id IN: mwoIDs];
                // Map<Id, Id> mwoToInstalledProMap = new Map<Id,Id>();

                MAP<Id,Master_Work_Order__c> mwoMap = new Map<Id,Master_Work_Order__c>([SELECT Id, Location__c, Installed_Product__c FROM Master_Work_Order__c WHERE Id IN: mwoIDs]);

                List<SVMXC__Service_Contract_Products__c> listOfCoveredProducts = new List<SVMXC__Service_Contract_Products__c>();
                List<SVMXC__Service_Contract_Sites__c> listOfCoveredLocation = new List<SVMXC__Service_Contract_Sites__c>();
                List<SVMXC__PM_Offering__c> listOfOfferings = new List<SVMXC__PM_Offering__c>();
                /*for ( Master_Work_Order__c mwo: mWOs){
                    if (String.isNotBlank(mwo.Installed_Product__c)) {
                        mwoToInstalledProMap.put(mwo.Id, mwo.Installed_Product__c);
                    }
                } */
                for(SVMXC__Service_Contract__c cons: contractList){
                  Master_Work_Order__c mWO = mwoMap.get(cons.Master_Work_Order__c);

                  if (mWO != null){

                    SVMXC__Service_Contract_Products__c coveredProducts = new SVMXC__Service_Contract_Products__c();
                    coveredProducts.SVMXC__Service_Contract__c = cons.id;
                    coveredProducts.SVMXC__Installed_Product__c = mWO.Installed_Product__c;
                    listOfCoveredProducts.add(coveredProducts);
                    SVMXC__Service_Contract_Sites__c coveredLocation = new SVMXC__Service_Contract_Sites__c();
                    coveredLocation.SVMXC__Service_Contract__c = cons.id;
                    coveredLocation.SVMXC__Site__c = mWO.Location__c;

                     listOfCoveredLocation.add(coveredLocation);

                    for (SVMXC__Service_Plan__c p : servicePlans) {
                      if (cons.SVMXC__Service_Plan__c == p.Id) {
                        for (SVMXC__PM_Offering__c offering : p.SVMXC__PM_Offerings__r) {
                            SVMXC__PM_Offering__c newOff = new SVMXC__PM_Offering__c();
                            newOff.SVMXC__PM_Plan_Template__c = offering.SVMXC__PM_Plan_Template__c;
                            newOff.SVMXC__Service_Contract__c = cons.Id;
                            //newOff.SVMXC__Service_Plan__c = p.Id;
                            listOfOfferings.add(newOff);
                        }
                      }
                    }
                  }
                }
                insert listOfCoveredProducts;
                insert listOfCoveredLocation;
                insert listOfOfferings; 
              }
            }
          }
        }
      }
    }
  }

  private static void setCurrency(QTT_Order__c qOrd){

    if(qOrd.Currency_Type__c == 'BPS'){ // if QTT Currency is BPS

        qOrd.CurrencyIsoCode = 'GBP'; // set currency to GBP

    } else if (qOrd.Currency_Type__c == 'YEN'){ // if QTT Currency is YEN

        qOrd.CurrencyIsoCode = 'JPY'; // set currency to JPY

    } else if (String.isBlank(qOrd.Currency_Type__c)){ // if QTT Currency is null
    
        qOrd.CurrencyIsoCode = 'USD'; // set currency to USD

    } else { // if QTT Currency is not one of the above

        qOrd.CurrencyIsoCode = qOrd.Currency_Type__c; // set currency same as QTT Currency
    }   
  }

  private static void setQuoteOrderStage(QTT_Order__c qOrd){
    System.debug('qOrd.QTT_Order_Status__c: '+qOrd.QTT_Order_Status__c);
    if (qOrd.QTT_Order_Status__c == 'HFR'){ // if HFR

      qOrd.StageName__c = 'Won - Hold For Release'; // set Stage to "Won - Hold For Release"

    } else if (qOrd.QTT_Order_Status__c == 'Partial' || qOrd.QTT_Order_Status__c == 'Released'){ // if Partial or Released

      qOrd.StageName__c = 'Won - Released'; // set Stage to "Won - Released"

    } else { // otherwise

      qOrd.StageName__c = qOrd.QTT_Order_Status__c; // set Stage equal to QTT_Order_Status__c
    }
  }

  // (LS-341 New Requirements 2/8/16)
  public static void resetOpportunityValuesForCancelledOrders(Set<ID> oppIDs){

    List<Opportunity> oppsToUpdateList = new List<Opportunity>(); // define list of opportunities to be updated

    // get Opportunities for cancelled orders
    List<Opportunity> oppList = new List<Opportunity>([SELECT Id, Amount, Forecast_Lutron__c, StageName, CloseDate, CurrencyIsoCode,
                                (SELECT Id, Quote_Value__c, CurrencyIsoCode, CreatedDate FROM QTT_Quote_Revisions__r ORDER BY CreatedDate Limit 1)
                                FROM Opportunity WHERE Id IN :oppIDs]);

    if (! oppList.isEmpty()){ // if Opportunities were found

      for (Opportunity opp : oppList){ // iterate thru Opportunities

        opp.Forecast_Lutron__c = '< 50%'; 
        opp.StageName = 'Out to Bid/Tender';
        opp.UnReleased_Amount__c = null;
        opp.QTT_Order_Status__c = null;

        System.debug(opp.QTT_Quote_Revisions__r);
        for (QTT_Quote_Revision__c qRev : opp.QTT_Quote_Revisions__r){ //iterate thru related Revisions

          opp.Amount = qRev.Quote_Value__c; // set the Opportunity Amount equal to the Revision Quote Value
          opp.CurrencyIsoCode = qRev.CurrencyIsoCode;
          opp.CloseDate = qRev.CreatedDate.Date().addDays(90); // reset the Opportunity Close Date to 90 days after the date of first Revision
          opp.Updated_From_First_Revision__c = true;
        }

        oppsToUpdateList.add(opp); // add Opportunity to the update list
        System.debug('opp is : '+opp);

      } // end of iteration thru Opportunities

      if (! oppsToUpdateList.isEmpty()){ // if there are Opportunities to update

        update oppsToUpdateList; // update the Opportunities
      }
    }
  } // END (LS-341 New Requirements 2/8/16)

  private static void unlinkRevisionsFromOpportunities(Set<Id> oppIDs){

    // get list of Revisions to unlink
    List<QTT_Quote_Revision__c> revsToUnlink = new List<QTT_Quote_Revision__c>([SELECT Id, Opportunity__c, QTT_Opportunity_RID__c, QuotedTo_ID__c FROM QTT_Quote_Revision__c WHERE Opportunity__c IN :oppIDs]);

    if (! revsToUnlink.isEmpty()){ // if Revisions were found

      Set<Id> acctIDs = new Set<Id>(); // define collection of Account Ids

      for (QTT_Quote_Revision__c rev : revsToUnlink){ // iterate thru Revisions

        rev.Opportunity__c = null; // set the Opportunity lookup to null
        rev.QTT_Opportunity_RID__c = null; // set the OpportunityRID to null

        acctIDs.add(rev.QuotedTo_ID__c); // add the Quoted To (Account) is to the collection
      }

      update revsToUnlink; // update the Revisions database

      if (! acctIDs.isEmpty()){ // if Account ids were collected

        // get Opportunity Partners to be removed
        List<Opportunity_Partner__c> oppPartnersToRemove = new List<Opportunity_Partner__c>([SELECT Id FROM Opportunity_Partner__c WHERE Account__c IN :acctIDs AND Opportunity__c IN :oppIDs]);

        if (! oppPartnersToRemove.isEmpty()){ // if Opportunity Partners were found

          delete oppPartnersToRemove; // remove Opportunity Partners from the database
        }
      }
    }
  }

  private static void linkQuotesToOpportunities(List<QTT_Order__c> qOrdersToLinkOpp){

    Set<Id> oppIDs = new Set<Id>(); // define collection of Opportunity ids

    for (QTT_Order__c qOrd : qOrdersToLinkOpp){ // iterate thru QuteOrders

      if (String.isNotBlank(qOrd.Opportunity__c)){ // if the QuoteOrder has an Opportunity

        oppIDs.add(qOrd.Opportunity__c); // add the Opportunity id to the collection
      }
    }

    // get Opportunities to be linked
    Map<ID,Opportunity> oppMap = new Map<ID,Opportunity>();

    if(!QTT_Quote_Revision_TriggerUtility.executionOppMap.isEmpty() && 
        QTT_Quote_Revision_TriggerUtility.executionOppMap.keySet().retainAll(oppIDs))
    {
        oppMap.putAll(QTT_Quote_Revision_TriggerUtility.executionOppMap);
    }
    else
    {
      oppMap = new Map<ID,Opportunity>([SELECT Id, OwnerId, Owner.IsActive, Amount, Bid_Date__c, Construction_Type__c,
                                                                  Installation_Type__c, QTT_RID__c, StageName, Vertical_Market__c
                                                          FROM Opportunity WHERE Id IN :oppIDs]);
    }

    if (! oppMap.isEmpty()){ // if Opportunities were found

      List<Opportunity_Link_History__c> oppLinkHistoriesToCreate = new List<Opportunity_Link_History__c>(); // define list of new Opportunity Link History records to create
      Opportunity opp; // define variable for existing Opportunity
      Opportunity_Link_History__c oLH; // define variable for new Opportunity Link History

      for (QTT_Order__c qOrd : qOrdersToLinkOpp){ // iterate thru QuoteOrders to be linked

        if (String.isNotBlank(qOrd.Opportunity__c)){ // if the QuoteOrder has an Opportunity

          opp = oppMap.get(qOrd.Opportunity__c); // get the Opportunity from the map

          if (opp != null){ // if the Opportunity was found in the map

            if (opp.Owner.IsActive){ // if the owner of the Opportunity is an active User

              qOrd.OwnerId = opp.OwnerId; //  make this User the owner of the QuoteOrder also
            }

            oLH = new Opportunity_Link_History__c(); // create a new Oppportunity Link History
            oLH.Amount__c = opp.Amount;
            oLH.Bid_Date__c = opp.Bid_Date__c;
            oLH.Construction_Type__c = opp.Construction_Type__c;
            oLH.Installation_Type__c = opp.Installation_Type__c;
            oLH.Opportunity_QTT_RID__c = opp.QTT_RID__c;
            oLH.Opportunity__c = opp.Id;
            oLH.Quote_Order_QTT_Ext_ID__c = qOrd.QTT_External_ID__c;
            oLH.Quote_Order__c = qOrd.Id;
            oLH.Stage__c = opp.StageName;
            oLH.Vertical_Market__c = opp.Vertical_Market__c;

            oppLinkHistoriesToCreate.add(oLH); // add the Opportunity Link History to the list
          }
        }
      }

      if (! oppLinkHistoriesToCreate.isEmpty()){ // if new Opportunity Link History objects were created

        insert oppLinkHistoriesToCreate; // save them to the database
      }
    }
  }
}