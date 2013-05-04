/**
 * Copyright (c) 2013, Stephen Willcock
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification, 
 *   are permitted provided that the following conditions are met:
 *
 * - Redistributions of source code must retain the above copyright notice, 
 *      this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright notice, 
 *      this list of conditions and the following disclaimer in the documentation 
 *      and/or other materials provided with the distribution.
 * - The name of the author may be not used to endorse or promote products derived from    
 *      this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND 
 *  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES 
 *  OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL 
 *  THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, 
 *  EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 *  OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 *  OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 *  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
**/

global virtual class LockingRuleHandler
{
	global static void handleTrigger()
	{
		if(Trigger.isExecuting && Trigger.isUpdate && Trigger.isAfter)
		{
			LockingRuleHandler instance = new LockingRuleHandler(Trigger.oldMap,Trigger.new);
			instance.handleAfterUpdate();
		}
	}

	Map<Id,sObject> m_oldMap; 
	List<sObject> m_newList;

	LockingRuleHandler() {}
	
	LockingRuleHandler(Map<Id,sObject> oldMap, List<sObject> newList)
	{
		m_oldMap = oldMap;
		m_newList = newList;
	}
	
	// TODO consider breaking this method down
	void handleAfterUpdate()
	{
		if(m_newList.isEmpty())
			return;
		if(m_newList[0].Id == null)
			return;
		String apiName = m_newList[0].Id.getSObjectType().getDescribe().getName();
		List<LockingRule__c> lockingRuleList = selectLockingRules(apiName);

		// We are currently only supporting a single rule per object type
		if(lockingRuleList.size()<>1)
			return;
		LockingRule__c lockingRule = lockingRuleList[0];

		JsonLockingRule jsonRule = (JsonLockingRule) JSON.deserialize(lockingRule.JSON__c, JsonLockingRule.class);
		
		for(sObject newRecord : m_newList)
		{
			Object stateObj = newRecord.get(lockingRule.StateFieldName__c);
			if(stateObj!=null)
			{	
				// We only support picklist (String) or checkbox (Boolean) state field types
				String state = stateObj instanceof String ? (String) stateObj : String.valueOf((Boolean)stateObj);
				Set<String> fieldNames = jsonRule.LockedFieldsByState.get(state);
				if(fieldNames!=null)
				{
					for(String fieldName : fieldNames)
					{
						sObject oldRecord = m_oldMap.get(newRecord.Id);
						if(oldRecord!=null && oldRecord.get(fieldName) != newRecord.get(fieldName))
						{
							addError(newRecord,String.format('Cannot change {0}, because of {3} Locking Rule when {1} is {2}', new List<String>{fieldName, lockingRule.StateFieldName__c, state, lockingRule.Name})); // TODO label
							break;
						}	
					}
				}
			}
		}
	}
	
	virtual List<LockingRule__c> selectLockingRules(String apiName)
	{
		return [select id, Name, ObjectAPIName__c, StateFieldName__c, JSON__c from LockingRule__c where ObjectAPIName__c = :apiName];
	}
	
	virtual void addError(sObject record, String message)
	{
		record.addError(message);
	}
	
	/*
	 * Tests
	 */

	static TestData s_testData = new TestData();

	class TLockingRuleHandler extends LockingRuleHandler
	{
		List<String> m_errorMessages = new List<String>();
		List<sObject> m_errorRecords = new List<sObject>();

		TLockingRuleHandler(Map<Id,sObject> oldMap, List<sObject> newList)
		{
			super(oldMap,newList);
		}

		override List<LockingRule__c> selectLockingRules(String apiName)
		{
			return new List<LockingRule__c> { s_testData.LockingRules.get(apiName) };
		}
		
		override void addError(sObject record, String message)
		{
			m_errorRecords.add(record);
			m_errorMessages.add(message);
		}
	}
	
	class TestData
	{
		Map<String,LockingRule__c> LockingRules = new Map<String,LockingRule__c>();
	}

	@isTest
	static void testNotLocked()
	{
		LockingRule__c lockingRule = new LockingRule__c(
			Name='MyLockingRule',
			ObjectAPIName__c=Opportunity.SobjectType.getDescribe().getName(),
			StateFieldName__c=Opportunity.StageName.getDescribe().getName() );
		JsonLockingRule jsonLockingRule = new JsonLockingRule();
		jsonLockingRule.putLock('Closed Won',Opportunity.StageName.getDescribe().getName());
		lockingRule.JSON__c = JSON.serialize(jsonLockingRule);
		s_testData.LockingRules.put(lockingRule.ObjectAPIName__c,lockingRule);
		
		Opportunity oldOpp = new Opportunity(Id = TestUtility.instance.getFakeId(Opportunity.SobjectType), Name='OriginalName', StageName='Closed Won');
		Opportunity newOpp = new Opportunity(Id = oldOpp.Id, Name='ChangedName', StageName='Closed Won');

		TLockingRuleHandler instance = new TLockingRuleHandler(new Map<Id,sObject>{oldOpp.Id=>oldOpp}, new List<sObject>{newOpp});
		instance.handleAfterUpdate();
		
		system.assert(instance.m_errorMessages.isEmpty());
	}

	@isTest
	static void testLocked()
	{
		LockingRule__c lockingRule = new LockingRule__c(
			Name='MyLockingRule',
			ObjectAPIName__c=Opportunity.SobjectType.getDescribe().getName(),
			StateFieldName__c=Opportunity.StageName.getDescribe().getName() );
		JsonLockingRule jsonLockingRule = new JsonLockingRule();
		jsonLockingRule.putLock('Closed Won',Opportunity.Name.getDescribe().getName());
		lockingRule.JSON__c = JSON.serialize(jsonLockingRule);
		s_testData.LockingRules.put(lockingRule.ObjectAPIName__c,lockingRule);
		
		Opportunity oldOpp = new Opportunity(Id = TestUtility.instance.getFakeId(Opportunity.SobjectType), Name='OriginalName', StageName='Closed Won');
		Opportunity newOpp = new Opportunity(Id = oldOpp.Id, Name='ChangedName', StageName='Closed Won');

		TLockingRuleHandler instance = new TLockingRuleHandler(new Map<Id,sObject>{oldOpp.Id=>oldOpp}, new List<sObject>{newOpp});
		instance.handleAfterUpdate();
		
		system.assertEquals(1,instance.m_errorMessages.size());
		system.assertEquals('Cannot change Name, because of MyLockingRule Locking Rule when StageName is Closed Won',instance.m_errorMessages[0]);
	}
}