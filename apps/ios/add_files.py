import sys
import uuid
import json
import re

# We need to add FreeTierLimits.swift, PaywallView.swift, and StoreManager.swift to Fleunce.xcodeproj
# The quickest way to compile without wrestling with pbxproj is to add them via bash script that modifies the pbxproj
# Or just copy them into an existing file! Wait, copying them into FleunceApp.swift is 100% foolproof and avoids project.pbxproj corruption.

