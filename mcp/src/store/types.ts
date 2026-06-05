export interface Source {
  id: number;
  name: string;
  path: string;
  droppedAt: number;
  removedAt: number | null;
}

export interface Gunk {
  id: number;
  sourceId: number;
  name: string;
  purpose: string | null;
  language: string | null;
  confidence: number | null;
  tags: string[];
  bundlePath: string | null;
  manifestPath: string | null;
  extractedAt: number | null;
  approvedAt: number | null;
  removedAt: number | null;
  canonicalGunkId: number;
  variantCount: number;
}

export interface GunkWithFiles extends Gunk {
  files: GunkFile[];
}

export interface GunkFile {
  id: number;
  gunkId: number;
  relpath: string;
  size: number | null;
}

export interface Tag {
  id: number;
  name: string;
}

export interface GunkTag {
  gunkId: number;
  tagId: number;
  tag: string;
  confidence: number | null;
}

export interface GunkEmbedding {
  gunkId: number;
  vector: number[];
  dim: number;
  model: string;
}
