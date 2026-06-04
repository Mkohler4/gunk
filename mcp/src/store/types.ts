export interface Gunk {
  id: number;
  name: string;
  path: string;
  droppedAt: number;
  removedAt: number | null;
}

export interface GunkFile {
  id: number;
  gunkId: number;
  relpath: string;
  size: number | null;
}

export interface Tag {
  name: string;
  description: string;
}

export interface GunkTag {
  gunkId: number;
  tag: string;
  confidence: number;
  source: "llm" | "manual" | "heuristic";
  taggedAt: number;
}
