## Troubleshooting

If you encounter any issues completing the lab, please refer to the following troubleshooting tips.

### pmapper can't enumerate IAM
Ensure your credentials have these permissions:
- `iam:GetAccountAuthorizationDetails`
- `iam:ListUsers`, `iam:ListRoles`, `iam:ListGroups`
- `iam:GetUserPolicy`, `iam:GetRolePolicy`, `iam:GetGroupPolicy`
- `iam:ListAttachedUserPolicies`, `iam:ListAttachedRolePolicies`

### Graph creation takes too long
For large accounts, pmapper can take several minutes. The iam-vulnerable infrastructure should complete in under 2 minutes.

### No escalation paths found
Verify that iam-vulnerable deployed successfully:
```bash
aws iam list-users | grep privesc
```

You should see users like `privesc7-AttachUserPolicy`, `privesc14-UpdatingAssumeRolePolicy`, etc.