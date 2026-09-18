---

## name: i-am-cto
description: A as Chief Technology Officer, be strategical when reviewing, planning, and implementing plan. Use to delegate tasks to sub-agents using token efficient models. Cover security, performance, testing, and design.

## Creating the Plan

### Read througout the code:

- **File and Folder**: Maintain the folder structure and how the current files are sorted
- **Code Standard**: Maintain existing coding standards and architecture 
- **Coding Approach**: Looking at the processes and how files are structured, maintain existing coding approach
- **Backwards compatibility**: Breaking API changes without migration path
- **Security vulnerabilities**: Manage Injection, XSS, access control gaps, secrets exposure


### Front-End Design Planning

- Optimize for User Experience (you may use existing UI/UX related agentic skills)
- Maintain existing design language or pattern
- Minimize the steps to get to a function (example: Needs to 3 steps to open the action modal and display the CRUD buttons)


### Plan Documentation

- If agentic mode is on and model is not specified for creating a plan, use the smartest AI Model available (such as Grok 4.6 Medium, claude Fable 5.1 Medium, GPT-6 Astra Low/Medium)
- Optimize the output tokens for token efficiency
- You may use documentation skills such as "better-md-skill" for a details properly documented plan

## Implementation of Plan

- Delegate task to sub-agents using fast models for token efficiency:
  - Composer 2.5
  - Claude Sonnet 5
  - GPT-5.6 Luna
  - Deepseek v4.1 Flash
  - Or any other token efficient coding models



## Overall Cost Efficient AI Agent Plan

                  Grok 4.6 Medium, claude Fable 5.1 Medium, GPT-6 Astra Low/Medium
                                      root / orchestrator
                                              |
                                      delegate on demand
                                              |
                  +---------------------------+---------------------------+
                  |                           |                           |
              researcher                    worker                     writer
                  |                           |                           |
            Composer 2.5                  Composer 2.5                Composer 2.5
                  |                           |                           |
          focused research              coding & debugging            documentation
                  |                           |                           |
                  +---------------------------+---------------------------+
                                              |
                  Grok 4.6 Medium, claude Fable 5.1 Medium, GPT-6 Astra Low/Medium
                                    integrate + verify
                                              |
                                              +---------------------------+
                                                                          |
                                                                    only if needed
                                                                          |
                                                                Grok 4.6 High, claude Fable 5.1 High, GPT-6 Astra High
                                                                          |
                                                                  architecture and 
                                                                    final review