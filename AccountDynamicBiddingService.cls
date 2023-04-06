@RestResource(urlMapping='/AccountDynamicBiddingService/v1.0/*') 
global with sharing class AccountDynamicBiddingService {
	@httpPut
	global static void doPut() {
		List<String> 		reqCustIdList 	= new List<String>();
		List<AccountBid> 	reqAccBidList;

		System.debug('AccountDynamicBiddingService.doPut entered');
		
		reqAccBidList = readAndValidateRequest(RestContext.request);
		if(reqAccBidList==null){
			return;
		}

        for(AccountBid ab: reqAccBidList){
        	reqCustIdList.add(ab.customerId);
        }
        
        List<Account> accounts = getSfdcAccountsMatchingCustomerIds(reqCustIdList);
        if(accounts==null){
        	return;
        }
	
        Map<String, Account> sfdcCustIdAccountMap = new Map<String, Account>();	
        Set<String> customerIdNotRequiringDMLUpdateSet = new Set<String>();//If flag value the same as existing Account Dynamic_Bidding__c flag; then no need to update account.
        for(Account a: accounts){
        	sfdcCustIdAccountMap.put(a.Dealer_ID__c, a);
        }
        System.debug('AccountDynamicBiddingService.doPut sfdcCustIdAccountMap: ' + sfdcCustIdAccountMap);
        System.debug('AccountDynamicBiddingService.doPut reqAccBidList: ' + reqAccBidList);
        try{	
	
        	for(AccountBid ab: reqAccBidList){
        		if(sfdcCustIdAccountMap.keySet().contains(ab.customerId)){ 
        			Account a = sfdcCustIdAccountMap.get(ab.customerId);
        			if(a.Dynamic_Bidding__c == ab.biddingFlag){
        				customerIdNotRequiringDMLUpdateSet.add(ab.customerId);
        			}else{
        				a.Dynamic_Bidding__c = ab.biddingFlag;
        				sfdcCustIdAccountMap.put(ab.customerId,a);
        			}
        		}else{
        			System.debug('AccountDynamicBiddingService.doPut could not find key in sfdcCustIdAccountMap: ' + ab.customerId);
        		}
        	}
        	System.debug('AccountDynamicBiddingService.doPut customerIdNotRequiringDMLUpdateSet: ' + customerIdNotRequiringDMLUpdateSet);
        	Map<String, Account> sfdcDupCustIdAccountMap = sfdcCustIdAccountMap.clone();
        	if(!customerIdNotRequiringDMLUpdateSet.isEmpty()){
        		for(String key: customerIdNotRequiringDMLUpdateSet){
        			sfdcCustIdAccountMap.remove(key);
        		}
        	}
        	Boolean hasSuccess=false;
        	Boolean hasFailure=false;
        	AccountBidResponse callResponse;
        	List<AccountBid> accAlreadySetList;
        	if(!customerIdNotRequiringDMLUpdateSet.isEmpty()){
        		// If all Bidding Flag Values are already set in SFDC, no need for DML
        		accAlreadySetList = new List<AccountBid>();
        		for(String custId: customerIdNotRequiringDMLUpdateSet){
        			Account a = sfdcDupCustIdAccountMap.get(custId);
        			AccountBid aBid = new AccountBid();
        			aBid.biddingFlag = a.Dynamic_Bidding__c;
        			aBid.customerId  = a.Dealer_ID__c;
        			aBid.updateStatus = SUCCESS_KEY;
        			accAlreadySetList.add(aBid);
        		}
        		hasSuccess=true;
        	}

        	if(sfdcCustIdAccountMap.values().isEmpty()){
        		if(hasSuccess){
        			System.debug('sfdcCustIdAccountMap.values() Empty, customerIdNotRequiringDMLUpdateSet has values ');
        			callResponse = new AccountBidResponse(SUCCESS_KEY,null,accAlreadySetList);
        			RestContext.response.responseBody = Blob.valueOf(callResponse.toString());
        			return;
        		}
        	}else{
        		System.debug('sfdcCustIdAccountMap.values() not Empty ');
        		List<Database.SaveResult> srList;
        		if(!hasSuccess){
        			callResponse = new AccountBidResponse(SUCCESS_KEY,null,new List<AccountBid>());
        		}else{
        			callResponse = new AccountBidResponse(SUCCESS_KEY,null,accAlreadySetList);
        		}
        		List<Account> accToUpdateList = sfdcCustIdAccountMap.values();
        		try{
        			
        			srList  = Database.update(accToUpdateList, false);
        			System.debug('Update results: ' + srList);
        			Integer index=0;

        			for(Database.SaveResult sr: srList){
        				AccountBid aBid = new AccountBid();
        				aBid.biddingFlag = accToUpdateList[index].Dynamic_Bidding__c;
        				aBid.customerId  = accToUpdateList[index].Dealer_ID__c;
        				
        				if(sr.isSuccess()){
        					hasSuccess = true;
        					aBid.updateStatus = SUCCESS_KEY;
        				}else{
        					hasfailure = true;
        					aBid.updateStatus = FAILURE_KEY;
        					aBid.updateErrorMessage = sr.getErrors()[0].getMessage();
        				}
        				callResponse.accBidList.add(aBid);
        				index++;
        			}

        		}catch(Exception e){
        			callResponse = new AccountBidResponse(FAILURE_KEY,(FAILED_TO_UPDATE_DATA_FAILURE_PREFIX_KEY + e.getMessage()),new List<AccountBid>());
        			System.debug('AccountDynamicBiddingService.doPut  Response: '  + callResponse.toString());
        			RestContext.response.responseBody = Blob.valueOf(callResponse.toString());
        			return;
        		}
        	}
        	if(!hasSuccess && hasfailure){
        		System.debug('All Updates Failed');
        		callResponse.status = FAILURE_KEY;
        		callResponse.errorMessage = ALL_UPDATES_FALED_KEY;
        	}else if(hasSuccess && hasFailure){
        		System.debug('Some Updates Failed');
        		callResponse.status = PARTIAL_SUCCESS_KEY;
        		if(PARTIAL_SUCCESS_KEY != SUCCESS_KEY){
        			callResponse.errorMessage = SOME_UPDATES_FALED_KEY;
        		}
        	}
			System.debug('AccountDynamicBiddingService.doPut  Response: '  + callResponse.toString());
        	RestContext.response.responseBody = Blob.valueOf(callResponse.toString()); 
        	return;
        	
        }catch(Exception e){        	
        	AccountBidResponse callResponse = new AccountBidResponse(FAILURE_KEY,e.getMessage(),new List<AccountBid>());
        	System.debug('AccountDynamicBiddingService.doPut  Response: '  + callResponse.toString());
        	RestContext.response.responseBody = Blob.valueOf(callResponse.toString());
        	return;
        }
	
	}
	
	global class AccountBid {
		global String customerId { get; set; }
		global Boolean biddingFlag { get; set; }
		global String updateStatus { get; set; }
		global String updateErrorMessage { get; set; }
		
		override  public String toString(){
			return JSON.serialize(this);
		}
	}
	
	global class AccountBidResponse {
		global String status { get; set; }
		global String errorMessage { get; set; }
		global List<AccountBid> accBidList { get; set; }
		
		global AccountBidResponse(){
			this.accBidList = new List<AccountBid>();
		}
		
		global AccountBidResponse(String status, String errorMessage, List<AccountBid> accountBidList){
			this.status = status;
			this.errorMessage = errorMessage;
			this.accBidList = accountBidList;
		}

		override global String toString(){
			if(this.accBidList==null){
				this.accBidList = new List<AccountBid>();
			}
			return JSON.serialize(this);
		}
	}
	
	@TestVisible
	private static List<AccountBid> readAndValidateRequest(RestRequest req){
		String jsonToParse;
		List<AccountBid> reqAccBidList;
		try{// Read and validate request

			jsonToParse=req.requestBody.toString(); 
			System.debug('AccountDynamicBiddingService.doPut  Request: '  + jsonToParse);
    		reqAccBidList=(List<AccountBid>)JSON.deserialize(jsonToParse, List<AccountBid>.class);
    		System.debug('AccountDynamicBiddingService.doPut  reqAccBidList: '  + reqAccBidList);
    		if(reqAccBidList==null || reqAccBidList.isEmpty() || (reqAccBidList[0].biddingFlag==null && reqAccBidList[0].customerId==null && reqAccBidList[0].updateStatus==null && reqAccBidList[0].updateErrorMessage==null)){
        		AccountBidResponse callResponse = new AccountBidResponse(FAILURE_KEY,NO_INPUT_FAILURE_MSG_KEY,new List<AccountBid>());
        		System.debug('AccountDynamicBiddingService.doPut  Response: '  + callResponse.toString());
        		RestContext.response.responseBody = Blob.valueOf(callResponse.toString());
        		return null;
        	}
    		return reqAccBidList;
    		
		}catch(Exception e){
			AccountBidResponse callResponse = new AccountBidResponse(FAILURE_KEY,FAILED_TO_PROCESS_FAILURE_PREFIX_KEY + e.getMessage(),new List<AccountBid>());
			System.debug('AccountDynamicBiddingService.doPut  Response: '  + callResponse.toString());
			RestContext.response.responseBody = Blob.valueOf(callResponse.toString());
			System.debug('AccountDynamicBiddingService.doPut failed to process Request: ' + e.getMessage() + ' JSON: ' + jsonToParse);
			return null;
		}
	}
	
	private static List<Account> getSfdcAccountsMatchingCustomerIds(List<String> reqCustIdList){
		List<Account> accounts;
		try{// Read current state of related Accounts

			String queryFields = ProductsDAO.queryObjectFields('Account', false);
			System.debug('AccountDynamicBiddingService.doPut getSfdcAccountsMatchingCustomerIds  queryFields: '  + queryFields);
			String delimiter = ',';
			String queryString = 'Select ' + queryFields + ' FROM Account WHERE Dealer_ID__c IN ('  + UtilString.stringListToDelimitedString(reqCustIdList, delimiter) + ')';
			System.debug('AccountDynamicBiddingService.doPut getSfdcAccountsMatchingCustomerIds  queryString: '  + queryString);
			accounts = Database.query(queryString);
        	System.debug('AccountDynamicBiddingService.doPut  accounts: '  + accounts);
        	if(accounts.isEmpty()){
        		AccountBidResponse callResponse = new AccountBidResponse(FAILURE_KEY,ACC_NOT_FOUND_FAILURE_MSG_KEY,new List<AccountBid>());
        		System.debug('AccountDynamicBiddingService.doPut  Response: '  + callResponse.toString());
        		RestContext.response.responseBody = Blob.valueOf(callResponse.toString());
        		return null;
        	}
        	return accounts;
        }catch(QueryException  qe){
        	AccountBidResponse callResponse = new AccountBidResponse(FAILURE_KEY,FAILED_TO_GET_ACC_FAILURE_PREFIX_KEY + qe.getMessage(),new List<AccountBid>());
        	System.debug('AccountDynamicBiddingService.doPut  Response: '  + callResponse.toString());
        	RestContext.response.responseBody = Blob.valueOf(callResponse.toString());
        	return null;
        }
	}
	
	
	public static final String SUCCESS_KEY = 'Success';
	public static final String PARTIAL_SUCCESS_KEY = 'Partial Success';
	//public static final String PARTIAL_SUCCESS_KEY = SUCCESS_KEY;
	public static final String STATUS_KEY = 'status';
	public static final String FAILURE_KEY = 'Failure';
	public static final String ERROR_MSG_KEY = 'errorMessage';
	public static final String ROW_SELECTION_KEY = 'customerId';
	public static final String COLUMN_NAME_KEY = 'biddingFlag';
	public static final String DB_ROW_SELECTION_KEY = 'Dealer_ID__c';
	public static final String DB_COLUMN_NAME_KEY = 'Dynamic_Bidding__c';
	public static final String ACC_NOT_FOUND_FAILURE_MSG_KEY = 'No accounts found matching customer Ids.';
	public static final String NO_INPUT_FAILURE_MSG_KEY = 'No Input Data.';
	public static final String FAILED_TO_PROCESS_FAILURE_PREFIX_KEY = 'Failed to process Request: '; 
	public static final String ALL_UPDATES_FALED_KEY = 'All attempted updates failed'; 
	public static final String SOME_UPDATES_FALED_KEY = 'Some attempted updates failed'; 
	public static final String FAILED_TO_GET_ACC_FAILURE_PREFIX_KEY = 'Failed to retrive account information: ';
	public static final String FAILED_TO_UPDATE_DATA_FAILURE_PREFIX_KEY = 'Failed to update data: '; 
	
	/*********************************************************************/
	/********************** JSON data structure **************************/
	/*********************************************************************
	Request:
	{
	  	[
			{
				"customerId": "1",
				"biddingFlag": true
			},
			...
	  	]
	}

	Response:
	{
		"status":"Success/Failure",
		"errorMessage":"Message"
		"accBidList": [
			{
				"customerId": "1",	<== Only Existing Accounts with given customer Id
				"biddingFlag": true,<== otherwise the key/value is ignored.
				"updateStaus": "Success/Failure",
				"updateErrorMessage":"Message for Failure"
			},
			...
		]
	}
	*********************************************************************/
}