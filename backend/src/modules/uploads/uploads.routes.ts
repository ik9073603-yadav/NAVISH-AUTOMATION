import { Router } from 'express';
import multer from 'multer';
import { randomUUID } from 'crypto';
import path from 'path';
import { requireAuth } from '../../middleware/auth';
import { supabase, ATTACHMENTS_BUCKET } from '../../lib/storage';

export const uploadsRouter = Router();
uploadsRouter.use(requireAuth);

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    if (!file.mimetype.startsWith('image/')) {
      return cb(new Error('Only image files are allowed'));
    }
    cb(null, true);
  },
});

uploadsRouter.post('/', (req, res, next) => {
  upload.single('file')(req, res, (err) => {
    if (err) return res.status(400).json({ error: err.message });
    next();
  });
}, async (req, res, next) => {
  try {
    if (!req.file) return res.status(400).json({ error: 'No file uploaded' });

    const { orgId } = req.user!;
    const ext = path.extname(req.file.originalname) || '.jpg';
    const filePath = `${orgId}/${randomUUID()}${ext}`;

    const { error } = await supabase.storage
      .from(ATTACHMENTS_BUCKET)
      .upload(filePath, req.file.buffer, { contentType: req.file.mimetype });

    if (error) return res.status(500).json({ error: error.message });

    const { data } = supabase.storage.from(ATTACHMENTS_BUCKET).getPublicUrl(filePath);

    res.status(201).json({ url: data.publicUrl });
  } catch (err) { next(err); }
});
