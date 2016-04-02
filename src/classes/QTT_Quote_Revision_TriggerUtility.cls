public class QTT_Quote_Revision_TriggerUtility {
	
	public static Map<Id, Opportunity> executionOppMap = new Map<Id, Opportunity>();

	public QTT_Quote_Revision_TriggerUtility() {
		
	}

	public static void handleBeforeInsert(List<QTT_Quote_Revision__c> newList){
		setRevisionFieldValues(newList);
	}

	public static void handleBeforeUpdate(Map<ID,QTT_Quote_Revision__c> oldMap, Map<ID,QTT_Quote_Revision__c> newMap){	
		setRevisionFieldValues(newMap.values());
	}
	
	public static void handleAfterInsert(Map<ID,QTT_Quote_Revision__c> newMap){

		Quote_OrderTriggerHandler.executionQTTQuoteRevisionMap.putAll(newMap);

		Set<ID> oppIDs = new Set<ID>(); // define collection of opportunity ids
		List<QTT_Quote_Revision__c> qRevsForOpportunityPartners = new List<QTT_Quote_Revision__c>(); // define list of Revisions that may need Opportunity Partners created

		for (QTT_Quote_Revision__c qRev : newMap.values()){ // iterate thru the revisions

			if(String.isNotBlank(qRev.Quote_Order__c))
			{	
				Quote_OrderTriggerHandler.executionQTTIdList.add(qRev.Quote_Order__c);
			}

			if (String.isNotBlank(qRev.Opportunity__c)){ // if the revision has an opportunity id

				oppIDs.add(qRev.Opportunity__c); // add the opportunity id to the collection

				if (String.isNotBlank(qRev.QuotedTo_ID__c)){ // if the revision has a Quoted To (Account) id

					qRevsForOpportunityPartners.add(qRev); // add Revision to the list
				}
			}
		}

		if (! oppIDs.isEmpty()){ // if opp ids were collected

			syncOpportunityAmount(oppIDs); // sync the Opportunity Amount from the Revision Quote Value if needed

			if (! qRevsForOpportunityPartners.isEmpty()){ // if Revisions with Opp & Account were found

				createOpportunityPartners(qRevsForOpportunityPartners); 
			}
		}

		setQuotedRevision(newMap.values());
	}

	public static void handleAfterUpdate(Map<ID,QTT_Quote_Revision__c> oldMap, Map<ID,QTT_Quote_Revision__c> newMap){

		Quote_OrderTriggerHandler.executionQTTQuoteRevisionMap.putAll(newMap);

		Set<ID> oppIDs = new Set<ID>(); // define collection of opportunity ids
		List<QTT_Quote_Revision__c> qRevsForOpportunityPartners = new List<QTT_Quote_Revision__c>(); // define list of Revisions that may need Opportunity Partners created
		List<QTT_Quote_Revision__c> qRevsForSettingOrderedRev = new List<QTT_Quote_Revision__c>(); // define list of Revisions where the QouteOrder lookup has been changed
		QTT_Quote_Revision__c oldRev;
		QTT_Quote_Revision__c newRev;

		for (QTT_Quote_Revision__c qRev : newMap.values()){ // iterate thru the revisions

			if(String.isNotBlank(qRev.Quote_Order__c))
			{	
				Quote_OrderTriggerHandler.executionQTTIdList.add(qRev.Quote_Order__c);
			}

			if (String.isNotBlank(qRev.Opportunity__c)){ // if the revision has an opportunity id

				oppIDs.add(qRev.Opportunity__c); // add the opportunity id to the collection

				if (String.isNotBlank(qRev.QuotedTo_ID__c)){ // if the revision has a Quoted To (Account) id

					oldRev = oldMap.get(qRev.Id); // get prior version of Revision
					newRev = newMap.get(qRev.Id); // get new version of Revision

					if (oldRev.Opportunity__c != newRev.Opportunity__c || oldRev.QuotedTo_ID__c != newRev.QuotedTo_ID__c){ // if the Opportunity lookup or the Quoted To (Account) lookup have changed

						qRevsForOpportunityPartners.add(qRev); // add the Revision to the list for potential Opportunity Partners to be created
					}
				}	
			}

			if (String.isNotBlank(qRev.Quote_Order__c) && qRev.Quote_Order__c != oldMap.get(qRev.Id).Quote_Order__c){ // QuoteOrder not null and changed form previous value

				qRevsForSettingOrderedRev.add(qRev); // add the Revision to the list
			}
		}

		if (! oppIDs.isEmpty()){ // if opp ids were collected

			syncOpportunityAmount(oppIDs); // sync the Opportunity Amount from the Revision Quote Value if needed

			if (! qRevsForOpportunityPartners.isEmpty()){ // if Revisions with changed Opp or Account were found

				createOpportunityPartners(qRevsForOpportunityPartners); 
			}
		}

		if (! qRevsForSettingOrderedRev.isEmpty()){ // if Revisions with changed QuoteOrder lookups were found

			setQuotedRevision(qRevsForSettingOrderedRev);
		}
	}

	private static void setQuotedRevision(List<QTT_Quote_Revision__c> quoteRevisions){
		List<QTT_Quote_Revision__c> revs = quoteRevisions;
		Map<String,QTT_Quote_Revision__c> revsByQuoteOrder = new Map<String,QTT_Quote_Revision__c>();
		Set<String> qOIDs = new Set<String>();

		for (QTT_Quote_Revision__c qRev : revs){
			qOIDs.add(qRev.Quote_Order__c);
			revsByQuoteOrder.put(qRev.Quote_Order__c, qRev);
		}

		if (qOIDs.size() > 0){
			List<QTT_Order__c> qOrdersToUpdate = [select Id, QTT_Ordered_Rev__c, Ordered_Revision__c from QTT_Order__c where Id in :qOIDs];

			if (qOrdersToUpdate.size() > 0){

				for (QTT_Order__c qOrder : qOrdersToUpdate){
					QTT_Quote_Revision__c qRev = revsByQuoteOrder.get(qOrder.Id);

					if (qrev != null){

						if (qOrder.QTT_Ordered_Rev__c == qRev.QTT_Revision_RID__c){

							qOrder.Ordered_Revision__c = qRev.Id;

						}
					}
				}

				update qOrdersToUpdate;
			}			
		}
	}

	private static void setRevisionFieldValues(List<QTT_Quote_Revision__c> qRevisions){

		Set<String> oppRIDs = new Set<String>(); // define collection of Opportunity RIDs
		Set<ID> acctIDs = new Set<ID>(); // define collection of Account ids
		Map<String,Opportunity> oppMap = new Map<String,Opportunity>(); // define map of Opportunities keyed by Opp RID
		List<Opportunity> oppList; // define list of opportunities
		Map<ID,Account> acctMap; // define map of Accounts

		for (QTT_Quote_Revision__c qRev : qRevisions){ // iterate thru revisions

			if (String.isNotBlank(qRev.QTT_Opportunity_RID__c)){ // if the rev has a Opp RID	
				System.debug('qRev.QTT_Opportunity_RID__c: '+qRev.QTT_Opportunity_RID__c);
				System.debug('qRev.Opportunity__c: '+qRev.Opportunity__c);

				oppRIDs.add(qRev.QTT_Opportunity_RID__c); // add the quote order id to the collection

			} else { // if Opp RID is null

				qRev.Opportunity__c = null; // set Opportunity lookup to null
			}

			if (String.isNotBlank(qRev.QuotedTo_ID__c)){ // if Revison has a Quoted to account

				acctIDs.add(qRev.QuotedTo_ID__c); // add the account id to the collection
			}

			setCurrency(qRev); // set the currency code
		}

		
		if (! oppRIDs.isEmpty()){ // if Opp RIDs were collected	

			oppList = new List<Opportunity>([SELECT Id, QTT_RID__c FROM Opportunity WHERE QTT_RID__c IN :oppRIDs]); // get Opportunities by RID

			if (! oppList.isEmpty()){ // if Opportunities were found

				for (Opportunity o : oppList){ // iterate thru Opportunities

					oppMap.put(o.QTT_RID__c, o); // add the Opportunity to the map
				}
			}
		}

		if (! acctIDs.isEmpty()){ // if account ids were collected

			acctMap = new Map<ID,Account>([SELECT Id, Name FROM Account WHERE Id IN :acctIDs]); // build map of quote orders
		}

		if (oppMap != null || acctMap != null){ // if there are Opportunities or Accounts related to the Revisions	
			System.debug('oppMap is: '+oppMap);
			System.debug('acctMap is: '+acctMap);

			for (QTT_Quote_Revision__c r : qRevisions){ // iterate thru revisions

				if (String.isNotBlank(r.QTT_Opportunity_RID__c)){ // if the rev has a Opp RID

					if (oppMap != null){

						Opportunity opp = oppMap.get(r.QTT_Opportunity_RID__c); // get the Opportunity from the map

						if (opp != null){ // if the Opportunity was found in the map

							r.Opportunity__c = opp.Id; // link the Revision to the Opportunity
						}
					}
				}

				if (String.isNotBlank(r.QuotedTo_ID__c)){ // if the rev has an Account id

					if (acctMap != null){

						Account a = acctMap.get(r.QuotedTo_ID__c); // get the Account from the Map

						if (a != null){ // if the Account was found in the map

							r.Quoted_To__c = a.Name; // set the Revision QuotedTo from the Account Name
						}
					}
				}
			}
		}
	}

	private static void setCurrency(QTT_Quote_Revision__c qRev){

        if(qRev.Currency_Type__c == 'BPS'){ // if QTT Currency is BPS

            qRev.CurrencyIsoCode = 'GBP'; // set currency to GBP

        } else if (qRev.Currency_Type__c == 'YEN'){ // if QTT Currency is YEN

            qRev.CurrencyIsoCode = 'JPY'; // set currency to JPY

        } else if (String.isBlank(qRev.Currency_Type__c)){ // if QTT Currency is null
        
            qRev.CurrencyIsoCode = 'USD'; // set currency to USD

        } else { // if QTT Currency is not one of the above

            qRev.CurrencyIsoCode = qRev.Currency_Type__c; // set currency same as QTT Currency
        }   
	}

	private static void syncOpportunityAmount(Set<ID> oppIDs){

		// check if Opportunity Processing is disabled
	  	Boolean getOut = checkOpportunitiesDisabled();
	  	if (getOut){
	    	return;
	  	} 

		if (! oppIDs.isEmpty()){ // if Opportunity ids were passed in

			List<Opportunity> oppsToUpdate = new List<Opportunity>(); // define list of opportunities that need to be updated

			// Get Opportunities that have not been "ordered" yet, have not been updated from first revison yet and get the first created Revision for each
			executionOppMap = new Map<Id, Opportunity>([SELECT Id, Amount, CurrencyIsoCode, Created_From_QTT_Integration__c, StageName, Updated_From_First_Revision__c,
																(SELECT Id, Quote_Value__c, CurrencyIsoCode 
																 FROM QTT_Quote_Revisions__r 
																 ORDER BY CreatedDate Limit 1), 
																(SELECT Id, Opportunity__c, Account__c, Account__r.Type, Account__r.Rating, Opportunity__r.StageName, Opportunity__r.Amount
		                                                         FROM Opportunity_Partners__r )
																FROM Opportunity WHERE Id IN :oppIDs]);

			if (!executionOppMap.isEmpty()){ // if Opportunities were found
				System.debug('oppList is: '+executionOppMap.values());

				Boolean updateOpp; // define variable used to determine if Opp needs to be updated
				Double quoteValue; // define variable used to store value to update Opportunity Amount with
				String currencyCode; // define varialble used to store Currency Code to update Opportunity

				for (Opportunity opp : executionOppMap.values()){ // iterate thru opportunities
					if(opp.StageName != null && !opp.StageName.startsWith('Won') && !opp.Updated_From_First_Revision__c)
					{
						System.debug('opp is: '+opp);

						// initialize variables for each new Opportunity
						updateOpp = false;
						quoteValue = 0;
						currencyCode = null;

						System.debug('opp.QTT_Quote_Revisions__r are: '+opp.QTT_Quote_Revisions__r);
						if (! opp.QTT_Quote_Revisions__r.isEmpty()){ // if the opportunity has a revision

							for (QTT_Quote_Revision__c r : opp.QTT_Quote_Revisions__r){ // iterate thru the revisions
								System.debug('r is: '+ r+'; and opp.Created_From_QTT_Integration__c is: '+opp.Created_From_QTT_Integration__c);

								if (opp.Created_From_QTT_Integration__c){ // if opp was created from QTT
									System.debug('r.Quote_Value__c is: '+r.Quote_Value__c);

									if (r.Quote_Value__c > 0){ // if Revision Quote Value greater than 0

										updateOpp = true; // Opportunity needs to be updated
										quoteValue = r.Quote_Value__c; // save Revision QuoteValue
										currencyCode = r.CurrencyIsoCode;
									}
									
								} else { // if Opp was not created from QTT
									System.debug('opp.Amount is: '+opp.Amount+'; and r.Quote_Value__c is: '+r.Quote_Value__c);

									if ((opp.Amount == 0 || opp.Amount == null) && r.Quote_Value__c > 0){ // if Opportunity Amount was not set by the user that created the Opportunity and the Revision QuoteValue > 0

										updateOpp = true; // Opportunity needs to be updated
										quoteValue = r.Quote_Value__c; // save Revision QuoteValue
										currencyCode = r.CurrencyIsoCode;
									}
								}
							}
						} 

						System.debug('updateOpp is: '+updateOpp+'; and quoteValue is: '+quoteValue+'; and currencyCode is: '+currencyCode);
						if (updateOpp){ // if this Opportunity needs to be updated

							opp.Amount = quoteValue; // set Opp Amount from Revison Quote Value
							opp.CurrencyIsoCode = currencyCode; // set Opp Currency from Revision Currency
							opp.Updated_From_First_Revision__c = true; // set the flag so Opportunoty does not get updated again form any Revisions
							oppsToUpdate.add(opp); // add the opportunity to the list

						}
					}
				} // get next Opportunity

				if (! oppsToUpdate.isEmpty()){ // if there are opportunities to update

					update oppsToUpdate; // update the database
				}
			}
		}
	}

	private static void createOpportunityPartners(List<QTT_Quote_Revision__c> qRevsForOpportunityPartners){

		// check if Opportunity Processing is disabled
		Boolean getOut = checkOpportunitiesDisabled();
		if (getOut){
		   	return;
		} 

		Set<Id> oppIDs = new Set<Id>(); // define collection of Opportunity ids
		Set<Id> acctIds = new Set<Id>();
		Map<Id, List<Opportunity_Partner__c>> opportunityListMap = new Map<Id, List<Opportunity_Partner__c>>();
		List<Opportunity_Partner__c> opportunityPartnerList = new List<Opportunity_Partner__c>();
		Map<Id, Opportunity> opportunityMap = new Map<Id, Opportunity>();

		For (QTT_Quote_Revision__c qRev : qRevsForOpportunityPartners){ // iterate thru Revisions

			if(executionOppMap.isEmpty())
			{
				if (String.isNotBlank(qRev.Opportunity__c) && String.isNotBlank(qRev.QuotedTo_ID__c)){ // if Revision has an Opportunity and a Quoted To (Account)

					oppIDs.add(qRev.Opportunity__c); // add the Opportunity id to the collection
				}
			}
			else
			{
				if (String.isBlank(qRev.QuotedTo_ID__c)){ // if Revision has an Opportunity and a Quoted To (Account)

					oppIDs.add(qRev.Opportunity__c); // add the Opportunity id to the collection
				}
			}
		}

		// get list of all Opportunity Partners that already exist for the Opportunities related to the Revisions
		List<Opportunity_Partner__c> oppPartnerList = new List<Opportunity_Partner__c>(); 

		if(executionOppMap.isEmpty() && !oppIDs.isEmpty())
		{
			oppPartnerList = new List<Opportunity_Partner__c>([SELECT Id, Opportunity__c, Account__c,
																						Account__r.Type, Account__r.Rating,
																						Opportunity__r.StageName, Opportunity__r.Amount
		                                                                                FROM Opportunity_Partner__c 
																						WHERE Opportunity__c IN :oppIDs]);
		}
		 else
		{
			for(Opportunity opp: executionOppMap.values())
			{
				if(!opp.Opportunity_Partners__r.isEmpty())
				{
					oppPartnerList.addAll(opp.Opportunity_Partners__r);
				}
			}
		}

		if (! oppPartnerList.isEmpty()){ // if Opportunity Partners were found

			Map<String,Opportunity_Partner__c> oppPartnersByOppAndAccount = new Map<String,Opportunity_Partner__c>(); // define map of Opportunity Partners keyed by Opp & Account combined

			String oppPartnerKey; // define variable used to hold the key value for the map

			for (Opportunity_Partner__c oppPart : oppPartnerList){ // iterate thru list of Opportunity Partners

				oppPartnerKey = oppPart.Opportunity__c+'.'+oppPart.Account__c; // create the unique key
				oppPartnersByOppAndAccount.put(oppPartnerKey,oppPart); // add the Opportunity Partner to the map

				if(oppPart.Opportunity__r.StageName != 'Duplicate' && oppPart.Opportunity__r.Amount != null && 
					(oppPart.Account__r.Type == 'Window System Provider Commercial' || oppPart.Account__r.Type == 'Specifier' || oppPart.Account__r.Type =='Builder' || oppPart.Account__r.Rating == 'AA - Top 10') 
                   && (oppPart.Account__r.Rating == 'AA - Top 10' || oppPart.Account__r.Type =='Specifier' || oppPart.Account__r.Type =='Builder'))
				{
					List<Opportunity_Partner__c> tempPartnerOppList;
                    if(opportunityListMap.containsKey(oppPart.opportunity__c))
                    {
                        tempPartnerOppList =  opportunityListMap.get(oppPart.opportunity__c);
                    }else{
                        tempPartnerOppList =  new List<Opportunity_Partner__c>();
                    }

                    tempPartnerOppList.add(oppPart);
                    opportunityListMap.put(oppPart.opportunity__c, tempPartnerOppList);
					
					opportunityMap.put(oppPart.Opportunity__c, new Opportunity(Id = oppPart.Opportunity__c, Amount = oppPart.Opportunity__r.Amount));
				}
			}

			List<Opportunity_Partner__c> oppPartnersToInsertList = new List<Opportunity_Partner__c>(); // define list of Opportunity Partners to be inserted into the database

			Opportunity_Partner__c oPart; // define variable for getting an existing Opportunity Partner from the map
			Opportunity_Partner__c newOP; // define variable for creating a new Opportunity Partner

			for (QTT_Quote_Revision__c qRev : qRevsForOpportunityPartners){ // iterate thru list of Revisions

				oppPartnerKey = qRev.Opportunity__c+'.'+qRev.QuotedTo_ID__c; // create the unique key
				oPart = oppPartnersByOppAndAccount.get(oppPartnerKey); // attempt to get the Opportunity Partner from the map

				if (oPart == null){ // if the Opportunity Partner was not found

					newOP = new Opportunity_Partner__c(); // create a new Opportunity Partner
					newOP.Opportunity__c = qRev.Opportunity__c; // set the Opportunity lookup
					newOP.Account__c = qRev.QuotedTo_ID__c; // set the Account lookup

					oppPartnersToInsertList.add(newOP); // add the new Opportunity Partner to the list

					acctIds.add(newOP.Account__c);
				}
			}

			if (! oppPartnersToInsertList.isEmpty()){ // if there are new Opportunity Partners

				OpportunityPartnerTriggerUtility.SplitOpportunityAmountForOppoPartnersInsertUpdate(oppPartnersToInsertList, acctIds, opportunityListMap, 
			                                                                                   opportunityPartnerList, opportunityMap);

				//insert oppPartnersToInsertList; // add the new Opportunity Partners to the database

				Database.SaveResult[] oppSR = Database.insert(oppPartnersToInsertList, false);

			    Integer i = 0;

			    for (Database.SaveResult sr : oppSR){

				    if (! sr.isSuccess()){

			          System.debug('Opportunity Partner was not created for Opportuntiy '+oppPartnersToInsertList[i].Opportunity__c+'; Account: '+oppPartnersToInsertList[i].Account__c+' due to error: '+sr.getErrors()[0]);
			        }

			        i++;
			      }
				}
		}
	}

  public static Boolean checkAllTriggersDisabled(){
    String setting = 'DISABLE ALL TRIGGERS';
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
}