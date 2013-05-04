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

public virtual with sharing class LockingRuleController
{
	/*
	 * Viewstate
	 */
	
	public Viewstate Viewstate {get;set;}
	
	public class Viewstate
	{
		public ApexPages.StandardController StandardController;
		public LockingRule__c Record;
	}
	
	public DetailViewstate DetailViewstate {get;set;}

	public class DetailViewstate
	{
		public List<FieldLockingView> FieldLockingViews {get;set;}
	}
	
	/*
	 * Constructor
	 */

	public LockingRuleController(ApexPages.StandardController standardController)
	{
		addFields(standardController);
		Viewstate = new Viewstate();
		Viewstate.StandardController = standardController;
		Viewstate.Record = (LockingRule__c) standardController.getRecord();
		
		if(getLockingRuleObjectsMap().keySet().isEmpty())
			ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.WARNING,'No objects have been configured for Locking Rules - manage the Locking Rules Custom Setting to add objects')); // TODO label
		
		// Retrieve the JSON locking rule representation from the database, and deseiralise into the DetailViewstate
		// Loaded the JSON separately so that it is not held in viewstate for the Standard Controller
		if(Viewstate.Record.Id!=null)
			initialiseLockingRules((JsonLockingRule) JSON.deserialize(selectLockingRuleJson(Viewstate.Record.Id),JsonLockingRule.class));
	}
	
	public LockingRuleController() {}
	
	// virtual : we will override this behaviour in apex tests
	virtual void addFields(ApexPages.StandardController standardController)
	{
		standardController.addFields(new List<String>{
			LockingRule__c.ObjectAPIName__c.getDescribe().getName(),
			LockingRule__c.StateFieldName__c.getDescribe().getName() }); 
	}

	// virtual : we will override this behaviour in apex tests
	virtual String selectLockingRuleJson(Id id)
	{
		List<LockingRule__c> result = [select JSON__c from LockingRule__c where Id=:id];
		return result.isEmpty() ? null : result[0].JSON__c;
	}
	
	/*
	 * Navigation
	 */
	
	public ApexPages.PageReference toEditFromNew()
	{
		Viewstate.Record.Name = getSelectedSobjectLabel();
		return Page.lockingruleedit;
	}		

	public ApexPages.PageReference save()
	{
		JsonLockingRule jsonRule = new JsonLockingRule();
		
		// Populate the JsonLockingRule prior to serialisation
		for(FieldLockingView fieldLockingView : DetailViewstate.FieldLockingViews)
		{
			for(String state : fieldLockingView.LockByState.keySet())
			{
				if(fieldLockingView.LockByState.get(state))
					jsonRule.putLock(state,fieldLockingView.Name);
			}
		}
		
		// Serialise the JSON and set it on the record ready to save
		Viewstate.Record.JSON__c = JSON.serialize(jsonRule);

		return doSave();
	}

	// virtual : we will override this behaviour in apex tests
	virtual ApexPages.PageReference doSave()
	{
		return Viewstate.StandardController.save();
	}

	/*
	 * SObject Type Selection
	 */	
	
	transient Map<String,SObjectType> t_sObjectTypeMap;
	transient SObjectType t_sObjectType;

	
	// Get the available object types as defined in the LockingRuleObjects__c custom setting as SelectOptions
	public List<SelectOption> getSobjectSelectOptions()
	{
		List<SelectOption> options = new List<SelectOption>();
		for(String item : getLockingRuleObjectsMap().keySet())
			options.add(new SelectOption(item,formatQualifiedLabel( ( getSobjectTypeMap().get(item)==null?'?????':getSobjectTypeMap().get(item).getDescribe().getLabel() ),item)));
		return options;
	}
	
	// virtual : we will override this behaviour in apex tests
	virtual Map<String,LockingRuleObjects__c> getLockingRuleObjectsMap()
	{
		return LockingRuleObjects__c.getAll();
	}

	Map<String,Schema.SObjectType> getSobjectTypeMap()
	{
		if(t_sObjectTypeMap == null)
			t_sObjectTypeMap = Schema.getGlobalDescribe();
		return t_sObjectTypeMap;
	}

	Schema.SObjectType getSelectedSobjectType()
	{
		if(t_sObjectType==null || t_sObjectType.getDescribe().getName()!=Viewstate.Record.ObjectApiName__c)
			t_sObjectType = getSobjectTypeMap().get(Viewstate.Record.ObjectApiName__c);
		return t_sObjectType;
	}
	
	String getSelectedSobjectLabel()
	{
		return getSelectedSobjectType().getDescribe().getLabel();
	}

	/*
	 * Edit Rules
	 */	

	public Boolean getStateFieldSelectDisabled()
	{
		return DetailViewstate!=null;
	}
	
	public void detailReset()
	{
		DetailViewstate = null;
		Viewstate.Record.StateFieldName__c = null;
	}

	public Boolean getRenderFieldLocks()
	{
		return DetailViewstate!=null;
	}

	// Get the fields which might be used to define the record's "state" for the selected sobject type as SelectOptions
	public List<SelectOption> getStateFieldSelectOptions()
	{
		List<SelectOption> result = new List<SelectOption>();
		Schema.SObjectType sObjectType = getSelectedSobjectType();
		result.add(new SelectOption('',''));
		if(sObjectType!=null)
		{
			for(Schema.SObjectField field : sObjectType.getDescribe().fields.getMap().values())
			{
				Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
				if((fieldDescribe.getType()==Schema.DisplayType.Boolean && fieldDescribe.getName()!='IsDeleted') || fieldDescribe.getType()==Schema.DisplayType.Picklist)
					result.add(new SelectOption(fieldDescribe.getName(),formatQualifiedLabel(fieldDescribe.getLabel(), fieldDescribe.getName())));
			}
		}
		return result;
	}

	Schema.SObjectField getSelectedStateFieldSobjectField()
	{
		Schema.SObjectType sObjectType = getSelectedSobjectType();
		return sObjectType==null ? null: sObjectType.getDescribe().fields.getMap().get(Viewstate.Record.StateFieldName__c);
	}
	
	public String getSelectedStateFieldLabel()
	{
		return getSelectedStateFieldSobjectField() == null ? null : getSelectedStateFieldSobjectField().getDescribe().getLabel(); 
	}
	
	// Return the available values for the "state" field 
	// We are only supporting checkbox and picklist fields to represent record "state"
	public List<String> getStateFieldValues()
	{
		Schema.SObjectField sobjectField = getSelectedStateFieldSobjectField();
		if(sobjectField==null)
			return new List<String>();
		if(sobjectField.getDescribe().getType()==Schema.DisplayType.Boolean)
			return new List<String> {'false','true'};
		if(sobjectField.getDescribe().getType()==Schema.DisplayType.Picklist)
		{
			List<String> result = new List<String>();
			for(Schema.PicklistEntry val : sobjectField.getDescribe().getPicklistValues())
			{
				result.add(val.getValue());
			}
			return result;
		}
		return new List<String>();
	}

	// Page Action
	public void initialiseLockingRules()
	{
		initialiseLockingRules(null);
	}

	// Set up the DetailViewstate using JsonLockingRule data if provided, otherwise all locks default to false
	void initialiseLockingRules(JsonLockingRule jsonRule)
	{
		DetailViewstate = new DetailViewstate();
		DetailViewstate.FieldLockingViews = new List<FieldLockingView>();
		Schema.SObjectType sObjectType = getSelectedSobjectType();
		if(sObjectType!=null)
		{
			for(Schema.SObjectField field : sObjectType.getDescribe().fields.getMap().values())
			{
				Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
				if(fieldDescribe.isUpdateable())
				{
					FieldLockingView flv = new FieldLockingView();
					flv.Name = fieldDescribe.getName(); 
					flv.Label = fieldDescribe.getLabel();
					flv.LockByState = new Map<String,Boolean>();
					for(String state : getStateFieldValues())
						flv.LockByState.put(state, jsonRule==null ? false : jsonRule.getLock(state, flv.Name));
					DetailViewstate.FieldLockingViews.add(flv);
				}
			}
		}
	}

	public class FieldLockingView
	{
		public String Name {get;set;}
		public String Label {get;set;}
		public Map<String,Boolean> LockByState {get;set;}
	}
	

	/*
	 * Utility
	 */	

	static String formatQualifiedLabel(String label, String name)
	{
		return String.format('{0} [{1}]', new List<String>{ label,name });
	}

	
	/*
	 * Tests
	 */	
	
	class TestEnvironment
	{
		String JsonString;
		LockingRule__c record;
		ApexPages.StandardController standardController;
		TLockingRuleController controller;
	}
	
	static TestEnvironment s_testEnvironment;
	
	class TLockingRuleController extends LockingRuleController
	{
		TLockingRuleController(ApexPages.StandardController standardController)
		{
			super(standardController);	
		}
		
		override String selectLockingRuleJson(Id id)
		{
			return s_testEnvironment.JsonString;
		}
		
		override void addFields(ApexPages.StandardController standardController)
		{
		}

		public override ApexPages.PageReference doSave()
		{
			return null;
		}
		
		override Map<String,LockingRuleObjects__c> getLockingRuleObjectsMap()
		{
			return new Map<String,LockingRuleObjects__c>{'Opportunity'=>new LockingRuleObjects__c(),'Account'=>new LockingRuleObjects__c()};
		}
		
	}

	@isTest
	static void test_formatQualifiedLabel()
	{
		system.assertEquals('foo [bar]',formatQualifiedLabel('foo','bar')); 
	}


	@isTest
	static void test_FieldLockingView()
	{
		FieldLockingView instance = new FieldLockingView();
		instance.Name = 'testName';
		instance.Label = 'testLabel';
		instance.LockByState = new Map<String,Boolean>{'testKey'=>true};
		system.assertEquals('testName',instance.Name);
		system.assertEquals('testLabel',instance.Label);
		system.assertEquals(true,instance.LockByState.get('testKey'));
	}
	
	@isTest
	static void test_Viewstate()
	{
		Viewstate instance = new Viewstate();
		LockingRule__c record = new LockingRule__c();
		ApexPages.StandardController controller = new ApexPages.StandardController(record);
		instance.Record = record;		
		instance.StandardController = controller;
		system.assertEquals(record,instance.Record);
		system.assertEquals(controller,instance.StandardController);
		system.assertEquals(record,instance.StandardController.getRecord());
	}
	
	@isTest
	static void test_DetailViewstate()
	{
		DetailViewstate instance = new DetailViewstate();
		FieldLockingView item1 = new FieldLockingView();
		item1.Name = 'item1';
		FieldLockingView item2 = new FieldLockingView();
		item2.Name = 'item2';
		List<FieldLockingView> items = new List<FieldLockingView>{item1,item2};
		instance.FieldLockingViews = items;
		system.assertEquals(items,instance.FieldLockingViews);		
	}
	
	@isTest
	static void test_init_new()
	{
		s_testEnvironment = new TestEnvironment();
		s_testEnvironment.record = new LockingRule__c();
		s_testEnvironment.standardController = new ApexPages.StandardController(s_testEnvironment.record);
		s_testEnvironment.controller = new TLockingRuleController(s_testEnvironment.standardController);
		system.assertNotEquals(null,s_testEnvironment.controller.Viewstate);		
		system.assertEquals(s_testEnvironment.standardController, s_testEnvironment.controller.Viewstate.StandardController);		
		system.assertEquals(s_testEnvironment.record, s_testEnvironment.controller.Viewstate.Record);
		system.assertEquals(null, s_testEnvironment.controller.DetailViewstate); 
	}

	@isTest
	static void test_init_edit()
	{
		s_testEnvironment = new TestEnvironment();
		JsonLockingRule jlr = new JsonLockingRule();
		jlr.putLock('state1','field1');
		s_testEnvironment.JsonString = JSON.serialize(jlr);
		s_testEnvironment.record = new LockingRule__c(Id=TestUtility.instance.getFakeId(LockingRule__c.SobjectType));
		s_testEnvironment.standardController = new ApexPages.StandardController(s_testEnvironment.record);
		s_testEnvironment.controller = new TLockingRuleController(s_testEnvironment.standardController);
		system.assertNotEquals(null,s_testEnvironment.controller.Viewstate);		
		system.assertEquals(s_testEnvironment.standardController, s_testEnvironment.controller.Viewstate.StandardController);		
		system.assertEquals(s_testEnvironment.record, s_testEnvironment.controller.Viewstate.Record);
		system.assertNotEquals(null,s_testEnvironment.controller.DetailViewstate); 
	}

	@isTest
	static void test_toEditFromNew()
	{
		s_testEnvironment = new TestEnvironment();
		s_testEnvironment.record = new LockingRule__c();
		s_testEnvironment.standardController = new ApexPages.StandardController(s_testEnvironment.record);
		s_testEnvironment.controller = new TLockingRuleController(s_testEnvironment.standardController);
		s_testEnvironment.controller.Viewstate.Record.ObjectApiName__c='Opportunity';
		ApexPages.PageReference pageref = s_testEnvironment.controller.toEditFromNew();
		system.assertEquals(Page.lockingruleedit.getURL(),pageref.getURL());
		system.assertEquals('Opportunity',s_testEnvironment.controller.Viewstate.Record.Name);
	}

	@isTest
	static void test_save_NoLocks()
	{
		s_testEnvironment = new TestEnvironment();
		s_testEnvironment.record = new LockingRule__c();
		s_testEnvironment.standardController = new ApexPages.StandardController(s_testEnvironment.record);
		s_testEnvironment.controller = new TLockingRuleController(s_testEnvironment.standardController);
		s_testEnvironment.controller.Viewstate.Record.ObjectApiName__c='Opportunity';
		s_testEnvironment.controller.toEditFromNew();
		s_testEnvironment.controller.Viewstate.Record.StateFieldName__c='Stage';
		s_testEnvironment.controller.initialiseLockingRules();
		s_testEnvironment.controller.save();
		system.assertEquals('{"LockedFieldsByState":{}}',s_testEnvironment.controller.Viewstate.Record.JSON__c);
	}

	@isTest
	static void test_save()
	{
		s_testEnvironment = new TestEnvironment();
		s_testEnvironment.record = new LockingRule__c();
		s_testEnvironment.standardController = new ApexPages.StandardController(s_testEnvironment.record);
		s_testEnvironment.controller = new TLockingRuleController(s_testEnvironment.standardController);
		s_testEnvironment.controller.Viewstate.Record.ObjectApiName__c='Opportunity';
		s_testEnvironment.controller.toEditFromNew();
		s_testEnvironment.controller.Viewstate.Record.StateFieldName__c='Stage';
		s_testEnvironment.controller.initialiseLockingRules();
		s_testEnvironment.controller.DetailViewstate.FieldLockingViews[0].LockByState.put('Prospecting',true);
		s_testEnvironment.controller.save();
		system.assertEquals('{"LockedFieldsByState":{"Prospecting":["' + s_testEnvironment.controller.DetailViewstate.FieldLockingViews[0].Name + '"]}}',s_testEnvironment.controller.Viewstate.Record.JSON__c);
	}

	@isTest
	static void test_getSobjectSelectOptions()
	{
		s_testEnvironment = new TestEnvironment();
		s_testEnvironment.record = new LockingRule__c();
		s_testEnvironment.standardController = new ApexPages.StandardController(s_testEnvironment.record);
		s_testEnvironment.controller = new TLockingRuleController(s_testEnvironment.standardController);
		List<SelectOption> result = s_testEnvironment.controller.getSobjectSelectOptions();
		Map<String,LockingRuleObjects__c> lroMap = s_testEnvironment.controller.getLockingRuleObjectsMap();
		system.assertEquals(lroMap.size(),result.size());
		for(SelectOption item : result)
		{
			system.assertNotEquals(null,lroMap.get(item.getValue()));
		}
	}

	@isTest
	static void test_getSobjectTypeMap()
	{
		s_testEnvironment = new TestEnvironment();
		s_testEnvironment.record = new LockingRule__c();
		s_testEnvironment.standardController = new ApexPages.StandardController(s_testEnvironment.record);
		s_testEnvironment.controller = new TLockingRuleController(s_testEnvironment.standardController);
		system.assertEquals(null,s_testEnvironment.controller.t_sObjectTypeMap);
		Map<String,Schema.SObjectType> result;
		result = s_testEnvironment.controller.getSobjectTypeMap();
		system.assertNotEquals(null,result);
		system.assertNotEquals(null,s_testEnvironment.controller.t_sObjectTypeMap);
		result = s_testEnvironment.controller.getSobjectTypeMap();
		system.assertNotEquals(null,result);
	}

	@isTest
	static void test_getSelectedSobjectType()
	{
		s_testEnvironment = new TestEnvironment();
		s_testEnvironment.record = new LockingRule__c(ObjectApiName__c='Opportunity');
		s_testEnvironment.standardController = new ApexPages.StandardController(s_testEnvironment.record);
		s_testEnvironment.controller = new TLockingRuleController(s_testEnvironment.standardController);
		system.assertEquals(null, s_testEnvironment.controller.t_sObjectType);
		Schema.SObjectType result;
		result = s_testEnvironment.controller.getSelectedSObjectType();
		system.assertNotEquals(null,result);
		system.assertEquals(Opportunity.SObjectType,result);
		system.assertNotEquals(null, s_testEnvironment.controller.t_sObjectType);
		result = s_testEnvironment.controller.getSelectedSObjectType();
		system.assertNotEquals(null,result);
		system.assertEquals(Opportunity.SObjectType,result);
	}

	@isTest
	static void test_getSelectedSobjectLabel()
	{
		s_testEnvironment = new TestEnvironment();
		s_testEnvironment.record = new LockingRule__c(ObjectApiName__c='Opportunity');
		s_testEnvironment.standardController = new ApexPages.StandardController(s_testEnvironment.record);
		s_testEnvironment.controller = new TLockingRuleController(s_testEnvironment.standardController);
		system.assertEquals('Opportunity', s_testEnvironment.controller.getSelectedSobjectLabel());
	}

	@isTest
	static void test_getStateFieldSelectDisabled()
	{
		s_testEnvironment = new TestEnvironment();
		s_testEnvironment.record = new LockingRule__c();
		s_testEnvironment.standardController = new ApexPages.StandardController(s_testEnvironment.record);
		s_testEnvironment.controller = new TLockingRuleController(s_testEnvironment.standardController);
		system.assert(!s_testEnvironment.controller.getStateFieldSelectDisabled());
		s_testEnvironment.controller.DetailViewstate = new DetailViewState();
		system.assert(s_testEnvironment.controller.getStateFieldSelectDisabled());
	}

	@isTest
	static void test_detailReset()
	{
		s_testEnvironment = new TestEnvironment();
		s_testEnvironment.record = new LockingRule__c(StateFieldName__c='testValue');
		s_testEnvironment.standardController = new ApexPages.StandardController(s_testEnvironment.record);
		s_testEnvironment.controller = new TLockingRuleController(s_testEnvironment.standardController);
		s_testEnvironment.controller.DetailViewstate = new DetailViewstate();
		system.assertNotEquals(null,s_testEnvironment.controller.DetailViewstate);
		system.assertNotEquals(null,s_testEnvironment.record.StateFieldName__c);
		s_testEnvironment.controller.detailReset();
		system.assertEquals(null,s_testEnvironment.controller.DetailViewstate);
		system.assertEquals(null,s_testEnvironment.record.StateFieldName__c);
	}
	
	@isTest
	static void test_getRenderFieldLocks()
	{
		s_testEnvironment = new TestEnvironment();
		s_testEnvironment.record = new LockingRule__c();
		s_testEnvironment.standardController = new ApexPages.StandardController(s_testEnvironment.record);
		s_testEnvironment.controller = new TLockingRuleController(s_testEnvironment.standardController);
		system.assert(!s_testEnvironment.controller.getRenderFieldLocks());
		s_testEnvironment.controller.DetailViewstate = new DetailViewState();
		system.assert(s_testEnvironment.controller.getRenderFieldLocks());
	}

	@isTest
	static void test_getStateFieldSelectOptions()
	{
		s_testEnvironment = new TestEnvironment();
		s_testEnvironment.record = new LockingRule__c();
		s_testEnvironment.standardController = new ApexPages.StandardController(s_testEnvironment.record);
		s_testEnvironment.controller = new TLockingRuleController(s_testEnvironment.standardController);
	}
	
	@isTest
	static void test_getSelectedStateFieldSobjectField()
	{
		Schema.SObjectField result;
		
		s_testEnvironment = new TestEnvironment();
		s_testEnvironment.record = new LockingRule__c(ObjectApiName__c='Opportunity',StateFieldName__c='IsWon');
		s_testEnvironment.standardController = new ApexPages.StandardController(s_testEnvironment.record);
		s_testEnvironment.controller = new TLockingRuleController(s_testEnvironment.standardController);
		result = s_testEnvironment.controller.getSelectedStateFieldSobjectField();
		system.assertEquals('IsWon',result.getDescribe().getName());

		s_testEnvironment = new TestEnvironment();
		s_testEnvironment.record = new LockingRule__c(ObjectApiName__c='Opportunity',StateFieldName__c=null);
		s_testEnvironment.standardController = new ApexPages.StandardController(s_testEnvironment.record);
		s_testEnvironment.controller = new TLockingRuleController(s_testEnvironment.standardController);
		result = s_testEnvironment.controller.getSelectedStateFieldSobjectField();
		system.assertEquals(null,result);

		s_testEnvironment = new TestEnvironment();
		s_testEnvironment.record = new LockingRule__c(ObjectApiName__c=null,StateFieldName__c='IsWon');
		s_testEnvironment.standardController = new ApexPages.StandardController(s_testEnvironment.record);
		s_testEnvironment.controller = new TLockingRuleController(s_testEnvironment.standardController);
		result = s_testEnvironment.controller.getSelectedStateFieldSobjectField();
		system.assertEquals(null,result);
	}

	@isTest
	static void test_getSelectedStateFieldLabel()
	{
		String result;
		
		s_testEnvironment = new TestEnvironment();
		s_testEnvironment.record = new LockingRule__c(ObjectApiName__c='Opportunity',StateFieldName__c='IsWon');
		s_testEnvironment.standardController = new ApexPages.StandardController(s_testEnvironment.record);
		s_testEnvironment.controller = new TLockingRuleController(s_testEnvironment.standardController);
		result = s_testEnvironment.controller.getSelectedStateFieldLabel();
		system.assertEquals(Schema.sObjectType.Opportunity.fields.IsWon.getLabel(),result);

		s_testEnvironment = new TestEnvironment();
		s_testEnvironment.record = new LockingRule__c(ObjectApiName__c='Opportunity',StateFieldName__c=null);
		s_testEnvironment.standardController = new ApexPages.StandardController(s_testEnvironment.record);
		s_testEnvironment.controller = new TLockingRuleController(s_testEnvironment.standardController);
		result = s_testEnvironment.controller.getSelectedStateFieldLabel();
		system.assertEquals(null,result);
	}
	
	@isTest
	static void test_getStateFieldValues()
	{
		List<String> result;
		
		s_testEnvironment = new TestEnvironment();
		s_testEnvironment.record = new LockingRule__c(ObjectApiName__c='Opportunity',StateFieldName__c='IsWon');
		s_testEnvironment.standardController = new ApexPages.StandardController(s_testEnvironment.record);
		s_testEnvironment.controller = new TLockingRuleController(s_testEnvironment.standardController);
		result = s_testEnvironment.controller.getStateFieldValues();
		system.assertEquals(new List<String> {'false','true'},result);

		s_testEnvironment = new TestEnvironment();
		s_testEnvironment.record = new LockingRule__c(ObjectApiName__c='Opportunity',StateFieldName__c='FooBar');
		s_testEnvironment.standardController = new ApexPages.StandardController(s_testEnvironment.record);
		s_testEnvironment.controller = new TLockingRuleController(s_testEnvironment.standardController);
		result = s_testEnvironment.controller.getStateFieldValues();
		system.assert(result.isEmpty());

		s_testEnvironment = new TestEnvironment();
		s_testEnvironment.record = new LockingRule__c(ObjectApiName__c='Opportunity',StateFieldName__c='StageName');
		s_testEnvironment.standardController = new ApexPages.StandardController(s_testEnvironment.record);
		s_testEnvironment.controller = new TLockingRuleController(s_testEnvironment.standardController);
		result = s_testEnvironment.controller.getStateFieldValues();
		Set<String> resultSet = new Set<String>(result);
		List<Schema.PicklistEntry> picklistEntries = Schema.sObjectType.Opportunity.fields.StageName.getPicklistValues();
		system.assertEquals(picklistEntries.size(),result.size());
		for(Schema.PicklistEntry picklistEntry : picklistEntries)
			system.assert(resultSet.contains(picklistEntry.getValue()));
	}

	@isTest
	static void test_initialiseLockingRules()
	{
		s_testEnvironment = new TestEnvironment();
		s_testEnvironment.record = new LockingRule__c(ObjectApiName__c='Opportunity',StateFieldName__c='IsWon');
		s_testEnvironment.standardController = new ApexPages.StandardController(s_testEnvironment.record);
		s_testEnvironment.controller = new TLockingRuleController(s_testEnvironment.standardController);

		Map<String, Schema.SObjectField> fieldMap = Schema.sObjectType.Opportunity.fields.getMap(); 
		Set<String> updateableFieldNames = new Set<String>();
		for(Schema.Sobjectfield field : fieldMap.values())
			if(field.getDescribe().isUpdateable())
				updateableFieldNames.add(field.getDescribe().getName());
		
		s_testEnvironment.controller.DetailViewstate = null;
		s_testEnvironment.controller.initialiseLockingRules();
		system.assertNotEquals(null,s_testEnvironment.controller.DetailViewstate);
		system.assertNotEquals(null,s_testEnvironment.controller.DetailViewstate.FieldLockingViews);
		system.assertEquals(updateableFieldNames.size(),s_testEnvironment.controller.DetailViewstate.FieldLockingViews.size());
		for(FieldLockingView item : s_testEnvironment.controller.DetailViewstate.FieldLockingViews)
		{
			system.assert(updateableFieldNames.contains(item.Name));
			system.assertNotEquals(null,fieldMap.get(item.Name),item.Name);
			system.assertEquals(fieldMap.get(item.Name).getDescribe().getLabel(),item.Label);
			// TODO test LockByState values
		}
	}
	
}