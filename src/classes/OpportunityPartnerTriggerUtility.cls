/*
Sno.    Date        Updated by        Changes Made
1       2/1/2014    Vinod.Kr          Added the method SplitOpportunityAmountForOppoPartnersInsertUpdate
2       2/1/2014    Vinod.Kr          Added the method SplitOpportunityAmountForOppoPartnersDelete
3       6/6/2014    Ankit.B           Updated the method SplitOpportunityAmountForOppoPartnersDelete
4       9/6/2014    Ankit.B           Updated the method SplitOpportunityAmountForOppoPartnersInsertUpdate
5       20/3/2015   Ankit.B           Updated the method SplitOpportunityAmountForOppoPartnersInsertUpdate for new spec dashboard
6       20/3/2015   Ankit.B           Updated the method SplitOpportunityAmountForOppoPartnersDelete for new spec dashboard
*/

public without sharing class OpportunityPartnerTriggerUtility {

    //List of Opportunity Partner records that have already been processed (Split Amount)
    //Used by the SplitOpportunityAmountForOppoPartnersInsertUpdate;
    public static Set<Id> opportunityPartnerId = new Set<Id>();
    
    //public static void handleBeforeDeleteTrigger(List<Opportunity_Partner__c> recs){
        
    //}
    
    public static void handleBeforeInsertTrigger(List<Opportunity_Partner__c> recs){
        
        Set<String> qttIds = new Set<String>();
        for(Opportunity_Partner__c op : recs){
            if(op.QTT_RID__c != null){
                qttIds.add(op.QTT_RID__c);
            }
        }
        
        Map<String,Opportunity> oMap = refreshOpportunities(qttIds);
        for(Opportunity_Partner__c op : recs){
            if(op.QTT_RID__c != null){
                Opportunity o = oMap.get(op.QTT_RID__c);
                if(o != null){
                    op.Opportunity__c = o.Id;
                }
            }
        }
        
    }

    public static void handleBeforeUpdateTrigger(List<Opportunity_Partner__c> recs){
        Set<String> qttIds = new Set<String>();
        for(Opportunity_Partner__c op : recs){
            if(op.QTT_RID__c != null){
                qttIds.add(op.QTT_RID__c);
            }
        }
        
        Map<String,Opportunity> oMap = refreshOpportunities(qttIds);
        for(Opportunity_Partner__c op : recs){
            if(op.QTT_RID__c != null){
                Opportunity o = oMap.get(op.QTT_RID__c);
                if(o != null){
                    op.Opportunity__c = o.Id;
                }
            }
        }
    }

    //public static void handleAfterDeleteTrigger(List<Opportunity_Partner__c> newRecs){
        
    //}
    
    public static void handleAfterInsertTrigger(List<Opportunity_Partner__c> recs, List<Opportunity_Partner__c> oldRecs){
        Set<Id> accountIds = new Set<Id>();
        for(Opportunity_Partner__c opp : recs){
            accountIds.add(opp.Account__c);
        }
        List<OpportunityTeamMember> otms = new List<OpportunityTeamMember>();
        //List<OpportunityShare> otss = new List<OpportunityShare>();
        Map<Id,Account> aMap = refreshAccounts(accountids);
            Map<ID,ID> ids = new Map<ID,ID>();
        for(Opportunity_Partner__c opp : recs){
            OpportunityTeamMember otm = new OpportunityTeamMember();
            //System.debug('Opportunity Partner Utility- Partner Opp '+ opp.Opportunity__c);
            //if(opp.Opportunity__c != ''){
            otm.OpportunityId = opp.Opportunity__c;
            Account a = aMap.get(opp.Account__c);
            if(a != null){
                otm.UserId = a.OwnerId;
                otm.TeamMemberRole = 'Area Team';
                if(opp.Account__c != ids.get(opp.Opportunity__c) ) //Added by Vinod to remove duplicate Ids on 7/12/2013
                {
                otms.add(otm);
                        ids.put(opp.Opportunity__c,opp.Account__c);
        }
            //}
            /*
            if(UserInfo.getUserType() == 'Standard'){
                OpportunityShare ots = new OpportunityShare();
                ots.UserOrGroupId = aMap.get(opp.Account__c).OwnerId;
                ots.OpportunityId = opp.Opportunity__c;
                ots.OpportunityAccessLevel = 'Edit';
                otss.add(ots);
            }
            */
        }
        if(otms.size() > 0){
            insert otms;    
        }
        
        //if (otss.size() >0){
        //  insert otss;    
        //}
        }
    }
    
    public static void handleAfterUpdateTrigger(List<Opportunity_Partner__c> recs, List<Opportunity_Partner__c> oldRecs){
        
    }
    
    //public static void handleAfterUnDeleteTrigger(List<Opportunity_Partner__c> recs){
        
    //}
    
    private static Map<Id,Account> refreshAccounts(Set<Id> accountids){
        Map<Id,Account> aMap = new Map<Id,Account>([Select Id, OwnerId From Account where id in:accountIds]);
        return aMap;
    }
    
    private static Map<String,Opportunity> refreshOpportunities(Set<String> qttRIDs){
        List<Opportunity> opps = new List<Opportunity>([Select Id, QTT_RID__c from Opportunity where QTT_RID__c in :qttRIDs]);
        Map<String,Opportunity> retMap = new Map<String,Opportunity>();
        for(Opportunity opp : opps){
            retMap.put(opp.QTT_RID__c, opp);
        }
        return retMap;
    }
    
    //split the amount of opportunity among the opportunity partners related with that opportunity whenever a partner opportunity is created or updated
    public static void SplitOpportunityAmountForOppoPartnersInsertUpdate(List<Opportunity_Partner__c> newoppoPartner, Set<Id>accountIdList, 
                                                                        Map<Id, List<Opportunity_Partner__c>> oppPartnertoOppMap, List<Opportunity_Partner__c> oppPartnerList,
                                                                        Map<Id, Opportunity> opportunityListMap)
    {
        if(LutronHelperUtility.flag==true)
        {
            system.debug('@@@@@@@@@@@@@@@@@@@@@@@@@@@@ executing SplitOpportunityAmountForOppoPartnersInsertUpdate '+newoppoPartner.size());
            
            //Map of Opportunity Id to List of Opportunity Partner
            Map<Id, List<Opportunity_Partner__c>> opportunityMap = new Map<Id, List<Opportunity_Partner__c>>();
            
            if(oppPartnerList == null)
            {
              //list of already existing Opportunity Partner
              oppPartnerList = new List<Opportunity_Partner__c>();
            }

            if(accountIdList == null)
            {
              //List of accounts associated with new Opportunity Partners
              accountIdList = new Set<Id>();

              for(Opportunity_Partner__c oppPa:newoppoPartner)
              {
                  if(oppPa.Account__c != null && !opportunityPartnerId.contains(oppPa.Id))
                  {
                      accountIdList.add(oppPa.Account__c);
                  }
              }
            }

            if(!accountIdList.isEmpty())
            {
                Map<Id, Account> accountMap = new Map<Id, Account>([SELECT Id FROM Account
                                                                    WHERE (Type='Window System Provider Commercial' or Type='Specifier' or Type='Builder' or Rating='AA - Top 10') 
                                                                           AND (Rating ='AA - Top 10' or Type ='Specifier' or Type ='Builder')
                                                                            AND Id IN: accountIdList]);

                //Build map of Opportunity Id to List of Opportunity Partner using trigger.new list
                for(Opportunity_Partner__c oppPa:newoppoPartner)
                {
                    if(oppPa.Account__c != null && accountMap.containsKey(oppPa.Account__c))
                    {
                        List<Opportunity_Partner__c> tempPartnerOppList;
                        if(opportunityMap.containsKey(oppPa.opportunity__c))
                        {
                            tempPartnerOppList =  opportunityMap.get(oppPa.opportunity__c);
                        }else{
                            tempPartnerOppList =  new List<Opportunity_Partner__c>();
                        }

                        tempPartnerOppList.add(oppPa);
                        opportunityMap.put(oppPa.opportunity__c, tempPartnerOppList);
                    }
                }

                if(!opportunityMap.isEmpty() && opportunityListMap == null)
                {
                    //Query for Opportunity with Opportunity Partner
                    opportunityListMap =new Map<Id, Opportunity>([SELECT name,amount,
                                                                                  (SELECT id,Split_Amount__c,Residential_Split_Amount__c
                                                                                   FROM Opportunity_Partners__r 
                                                                                   WHERE (account__r.type='Window System Provider Commercial' or account__r.type='Specifier' or account__r.type='Builder' or account__r.Rating='AA - Top 10') 
                                                                                    and  (account__r.Rating ='AA - Top 10' or account__r.type ='Specifier' or account__r.type ='Builder'))
                                                                                FROM Opportunity where id in:opportunityMap.keySet() and StageName!='Duplicate' AND Amount != null]);

                    for(opportunity opp:opportunityListMap.values())
                    {
                        System.debug('---------------------------------->>'+ opp.opportunity_partners__r.size());
                        for(Opportunity_Partner__c oppPar:opp.Opportunity_Partners__r)
                        {
                            List<Opportunity_Partner__c> tempPartnerOppList = opportunityMap.get(opp.Id);
                            tempPartnerOppList.add(oppPar);
                            opportunityMap.put(opp.Id, tempPartnerOppList);
                            oppPartnerList.add(oppPar);
                            opportunityPartnerId.add(oppPar.Id);
                        }
                    }
                }
                 else if(oppPartnertoOppMap != null)
                {
                  opportunityMap.putAll(oppPartnertoOppMap);
                }

                for(Id oppId: opportunityMap.keySet())
                {
                    if(opportunityListMap.get(oppId) != null)
                    {                    
                      Decimal amt = opportunityListMap.get(oppId).amount/opportunityMap.get(oppId).size();
                      System.debug('Number of Opportunity Partner records ' + opportunityMap.get(oppId).size());
                      System.debug('Split Amount' + amt);
    
                      for(Opportunity_Partner__c oppPar: opportunityMap.get(oppId))
                      { 
                        oppPar.Split_Amount__c = amt;
                      }
                     }
                }
                     
                if(oppPartnerList.size()!=0)    
                {
                  update oppPartnerList;
                }
            }
        }

        LutronHelperUtility.flag=false;
    }

    /* Commented by VinodK for ServiceMax Migration on 03/23/2016
     * //split the amount of opportunity among the opportunity partners related with that opportunity whenever a partner opportunity is deleted    
    public void SplitOpportunityAmountForOppoPartnersDelete(map<id,Opportunity_Partner__c > oldOppPartner)
        {set<id> oppid=new set<id>();
         for(Opportunity_Partner__c oppPa:oldOppPartner.values())
         {oppid.add(oppPa.opportunity__c);
         }
         map<id,opportunity> mapOpportunity=new map<id,opportunity>([select name,amount,(select id,Split_Amount__c,Residential_Split_Amount__c,account__r.type,account__r.Rating from Opportunity_Partners__r where (account__r.type='Window System Provider Commercial' or account__r.type='Specifier' or account__r.type='Builder' or account__r.Rating='AA - Top 10') and id not in:trigger.oldmap.keyset()) from opportunity where id in:oppid and StageName!='Duplicate']);
         map<id,Opportunity_Partner__c> mapOppPa=new map<id,Opportunity_Partner__c>();
         for(opportunity opp:mapOpportunity.values())
         {//map<id,Opportunity_Partner__c> specifierAccOppPa=new map<id,Opportunity_Partner__c>();
          map<id,Opportunity_Partner__c> ratingAccOppPa=new map<id,Opportunity_Partner__c>();
          if(opp.Opportunity_Partners__r.size()!=0 && opp.amount!=null)
            {    for(Opportunity_Partner__c oppPar:opp.Opportunity_Partners__r)
                     {/*
                      if(oppPar.account__r.type=='Specifier' || oppPar.account__r.type=='Window System Provider Commercial')
                        specifierAccOppPa.put(oppPar.id,oppPar);  
                        
                      if(oppPar.account__r.Rating=='AA - Top 10' || oppPar.account__r.type=='Specifier' || oppPar.account__r.type=='Builder')
                        ratingAccOppPa.put(oppPar.id,oppPar);     
                     }
                     /*
                 if(specifierAccOppPa.values().size()!=0)
                     {decimal amt=opp.amount/specifierAccOppPa.values().size();
                      for(Opportunity_Partner__c oppPar:specifierAccOppPa.values())
                         {if(mapOppPa.containskey(oppPar.id))
                             {Opportunity_Partner__c tempPartnerOpp=mapOppPa.get(oppPar.id);
                              tempPartnerOpp.Split_Amount__c=amt;
                              mapOppPa.put(oppPar.id,tempPartnerOpp);
                             }
                          else
                              {oppPar.Split_Amount__c=amt;
                               mapOppPa.put(oppPar.id,oppPar);
                              }
                         }
                     }
                     
                 if(ratingAccOppPa.values().size()!=0)
                     {decimal amt=opp.amount/ratingAccOppPa.values().size();
                      for(Opportunity_Partner__c oppPar:ratingAccOppPa.values())
                         {if(mapOppPa.containskey(oppPar.id))
                             {Opportunity_Partner__c tempPartnerOpp=mapOppPa.get(oppPar.id);
                              tempPartnerOpp.Residential_Split_Amount__c =amt;
                              mapOppPa.put(oppPar.id,tempPartnerOpp);
                             }
                          else
                              {oppPar.Residential_Split_Amount__c =amt;
                               mapOppPa.put(oppPar.id,oppPar);
                              }
                         }
                     }
            }
        }
        LutronHelperUtility.flag=false;
         if(mapOppPa.values().size()!=0)    
            update mapOppPa.values();
        }    */
}