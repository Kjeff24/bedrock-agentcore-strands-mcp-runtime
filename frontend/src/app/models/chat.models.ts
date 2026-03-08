export interface MessageContentItem {
  text: string;
}

export interface AssistantMessage {
  role: string;
  content: MessageContentItem[];
}

export interface AgentResponse {
  result?: AssistantMessage | string;
}

export interface ChatMessage {
  role: 'user' | 'assistant';
  content: string;
}
