"""
    LLDB Support for Deferred

    Add the following to your .lldbinit file to add Deferred Type summaries in LLDB and Xcode:

    command script import {Path to Deferred}/Tools/lldb/lldb_webkit.py

"""

import lldb
import string
import struct

def __lldb_init_module(debugger, dict):
    debugger.HandleCommand('type synthetic add -x "Deferred.Deferred<.+>$" --python-class lldb_deferred.DeferredProvider')

# class SyntheticChildrenProvider:
#     def __init__(self, valobj, internal_dict):
#         this call should initialize the Python object using valobj as the variable to provide synthetic children for
#     def num_children(self):
#         this call should return the number of children that you want your object to have
#     def get_child_index(self,name):
#         this call should return the index of the synthetic child whose name is given as argument
#     def get_child_at_index(self,index):
#         this call should return a new LLDB SBValue object representing the child at the index given as argument
#     def update(self):
#         this call should be used to update the internal state of this Python object whenever the state of the variables in LLDB changes.[1]
#     def has_children(self):
#         this call should return True if this object might have children, and False if this object can be guaranteed not to have children.[2]
#     def get_value(self):
#         this call can return an SBValue to be presented as the value of the synthetic value under consideration.[3]

class DeferredProvider:
    def __init__(self, valobj, internal_dict):
        # print("init")
        self.valobj = valobj
        # self.int_type = valobj.GetType().GetBasicType(lldb.eBasicTypeInt)
        # self.update()

    def num_children(self):
        # print("chillins")
        return 2

    def get_child_index(self, name):
        # print("child index")
        if name == "A":
            return 0
        elif name == "X":
            return 1
        else:
            return None

    def get_child_at_index(self, index):
        # print("child at index")
        if index == 0:
            return self.valobj.GetChildMemberWithName('A')
        elif index == 1:
            return self.valobj.GetTarget().CreateValueFromExpression('X', 'debugValue')
        else:
            return None

    def update(self):
        # print(self.valobj.GetChildMemberWithName("debugValue"))
        self.data_type = self.valobj.GetType().GetTemplateArgumentType(0)
        self.data_size = self.data_type.GetByteSize()
        print(self.valobj)

    def has_children(self):
        return True
